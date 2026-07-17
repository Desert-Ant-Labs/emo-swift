// On-device multilingual emoji suggestion for JavaScript, server-side (Node).
// This is the `node` conditional-exports entry: it runs the same Emo pipeline as
// the browser build, but natively via the prebuilt Swift core (LiteRT under the
// hood) instead of WebAssembly + LiteRT.js. Consumers just `import { Emo }` —
// Node resolves this file, browsers resolve `browser.js`. No flags, no setup.

import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import os from "node:os";
import path from "node:path";
import fs from "node:fs";

const require = createRequire(import.meta.url);
const koffi = require("koffi");
const HERE = path.dirname(fileURLToPath(import.meta.url));

const SKIN_TONES = { default: 0, light: 1, mediumLight: 2, medium: 3, mediumDark: 4, dark: 5 };

// The prebuilt native for this host lives in native/<platform>-<arch>/ next to
// this file (built by `mise run node-natives`): the self-contained Swift core
// (libEmoNode) plus the LiteRT runtime it links (libLiteRt). The core's runpath
// is `$ORIGIN`, so the two sit side by side and resolve with no LD_LIBRARY_PATH.
function nativeDir() {
  const key = `${process.platform}-${process.arch}`;
  const dir = path.join(HERE, "native", key);
  if (!fs.existsSync(dir)) {
    throw new Error(
      `@desert-ant-labs/emo: no prebuilt native for ${key}. ` +
        `Supported server-side targets: linux-x64, linux-arm64, darwin-arm64. ` +
        `Use the Swift package or a browser on this platform.`);
  }
  return dir;
}

const RUNTIME = { linux: "libLiteRt.so", darwin: "libLiteRt.dylib", win32: "LiteRt.dll" };
const CORE = { linux: "libEmoNode.so", darwin: "libEmoNode.dylib", win32: "EmoNode.dll" };

let lib;
function loadLib() {
  if (lib) return lib;
  const dir = nativeDir();
  // Load the LiteRT runtime first so the core's DT_NEEDED resolves in-process.
  const runtime = RUNTIME[process.platform];
  if (runtime && fs.existsSync(path.join(dir, runtime))) koffi.load(path.join(dir, runtime));
  const core = koffi.load(path.join(dir, CORE[process.platform] || CORE.linux));
  lib = {
    create: core.func("void* emo_create(const char*, const char*)"),
    createBundledPath: core.func("void* emo_create_bundled_path(const char*, uint8_t*, int, const char*)"),
    isDownloaded: core.func("int emo_is_downloaded(void*)"),
    download: core.func("int emo_download(void*)"),
    run: core.func("void* emo_run(void*, const char*, int, int)"),
    destroy: core.func("void emo_destroy(void*)"),
    stringFree: core.func("void emo_string_free(void*)"),
  };
  return lib;
}

// Run a blocking native function on a libuv worker thread (koffi async) so the
// Node event loop stays free during download and inference.
function callAsync(fn, ...args) {
  return new Promise((resolve, reject) => {
    fn.async(...args, (err, res) => (err ? reject(err) : resolve(res)));
  });
}

/** Decode the FFI buffer the core returns: a big-endian uint32 length prefix,
 *  then the payload (u32 count, then per suggestion a u32-length UTF-8 emoji
 *  string and an IEEE-754 double confidence). Mirrors `emo_run` in
 *  Sources/EmoAndroid/CABI.swift and the Kotlin FfiReader. */
function decodeSuggestions(ptr) {
  const head = Buffer.from(koffi.decode(ptr, koffi.array("uint8", 4)));
  const len = head.readUInt32BE(0);
  const payload = Buffer.from(koffi.decode(ptr, koffi.array("uint8", 4 + len))).subarray(4);
  let o = 0;
  const u32 = () => { const v = payload.readUInt32BE(o); o += 4; return v; };
  const f64 = () => { const v = payload.readDoubleBE(o); o += 8; return v; };
  const str = () => { const n = u32(); const s = payload.toString("utf8", o, o + n); o += n; return s; };
  const count = u32();
  const out = [];
  for (let i = 0; i < count; i++) {
    const emoji = str();
    const confidence = f64();
    out.push({ emoji, confidence });
  }
  return out;
}

/**
 * On-device multilingual emoji suggestion. Create one with `await Emo.load(...)`
 * and reuse it, mirroring the browser SDK and the iOS/Swift SDK.
 *
 * ```js
 * const emo = await Emo.load();                        // downloads the model on demand, cached
 * const suggestions = await emo.suggestions("Pay my bills");  // [{ emoji, confidence }, ...]
 * emo.dispose();                                       // free the native handle when done
 * ```
 */
export class Emo {
  #handle;
  constructor(handle) { this.#handle = handle; }

  /**
   * Load the model and return a ready suggester. Download, SHA-256 verification,
   * and caching are handled by the native core; the repo and revision are
   * pinned to the SDK.
   */
  static async load(options = {}) {
    const l = loadLib();
    const onProgress = typeof options.onProgress === "function" ? options.onProgress : undefined;
    let handle;
    if (options.directory == null) {
      // Emo is small, so the npm package ships the model and loads it by default.
      // The server-side native runs LiteRT on Linux (from the .tflite) and Core
      // ML on macOS (from the compiled .mlmodelc directory); pass this host's
      // artifact by path - one primitive, both runtimes, no network or cache.
      const modelDir = path.join(HERE, "model");
      const meta = fs.readFileSync(path.join(modelDir, "emo_meta.json"), "utf8");
      const tokenizer = new Uint8Array(fs.readFileSync(path.join(modelDir, "emo_tokenizer.bin")));
      const artifact = process.platform === "darwin" ? "emo.mlmodelc" : "emo.tflite";
      handle = l.createBundledPath(meta, tokenizer, tokenizer.byteLength, path.join(modelDir, artifact));
      onProgress?.(1);
    } else {
      // An explicit directory opts into adopt-or-download behavior.
      const cacheRoot = options.cacheRoot ?? path.join(os.homedir(), ".cache");
      handle = l.create(cacheRoot, options.directory);
    }
    if (!handle) throw new Error("@desert-ant-labs/emo: failed to create suggester");
    const emo = new Emo(handle);
    // With an explicit directory, ready the model now (download if needed) so
    // the first suggestion is instant and load() surfaces any download error.
    if (options.directory != null && l.isDownloaded(handle) === 0) {
      onProgress?.(0);
      const rc = await callAsync(l.download, handle);
      if (rc !== 0) { emo.dispose(); throw new Error("@desert-ant-labs/emo: model download failed"); }
      onProgress?.(1);
    }
    return emo;
  }

  /**
   * Suggest emojis for `text`, most likely first. Returns up to `limit`
   * `{ emoji, confidence }` suggestions; empty input returns `[]`.
   */
  async suggestions(text, options = {}) {
    if (!this.#handle) throw new Error("@desert-ant-labs/emo: suggester disposed");
    const phrase = String(text ?? "");
    if (phrase.trim() === "") return [];
    const l = loadLib();
    const limit = options.limit ?? 3;
    const skinTone = SKIN_TONES[options.skinTone ?? "default"] ?? 0;
    const ptr = await callAsync(l.run, this.#handle, phrase, limit, skinTone);
    if (!ptr) throw new Error("@desert-ant-labs/emo: suggestion failed");
    try {
      return decodeSuggestions(ptr);
    } finally {
      l.stringFree(ptr);
    }
  }

  /** Free the native handle. Call when you are done with the suggester. */
  dispose() {
    if (this.#handle) { loadLib().destroy(this.#handle); this.#handle = null; }
  }
}

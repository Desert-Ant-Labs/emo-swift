// On-device emoji suggestion for JavaScript. This file resolves model assets,
// owns the LiteRT.js session, and exposes the public typed API (an `Emo` class
// with an async `load` factory).
//
// Works in node and browsers via @litertjs/core (LiteRT.js): XNNPACK-accelerated
// CPU ("wasm") by default, with optional WebGPU in the browser.

const IS_NODE = typeof process !== "undefined" && !!process.versions?.node;

const SKIN_TONES = {
  default: 0, light: 1, mediumLight: 2, medium: 3, mediumDark: 4, dark: 5,
};

// The wasm core instantiates at import time (top-level await); the model is
// only wired in load().
async function instantiateCore() {
  globalThis.__EmoHost ??= {};
  const { instantiate } = await import("./dist/instantiate.js");
  if (IS_NODE) {
    // Give the Swift ModelStore node's fs as a platform seam (no `require`
    // under the WASI shim); the download/verify/cache logic stays in Swift.
    const fsmod = await import("node:fs");
    globalThis.__DalNodeFS = {
      existsSync: fsmod.existsSync, statSync: fsmod.statSync,
      // Copy into an exact-length Uint8Array: node returns pooled Buffers for
      // small files whose .buffer is the whole shared pool, which JavaScriptKit
      // would over-read when marshalling into wasm memory.
      readFileSync: (p) => new Uint8Array(fsmod.readFileSync(p)),
      writeFileSync: fsmod.writeFileSync,
      mkdirSync: fsmod.mkdirSync, renameSync: fsmod.renameSync, unlinkSync: fsmod.unlinkSync,
    };
    const { defaultNodeSetup } = await import("./dist/platforms/node.js");
    await instantiate(await defaultNodeSetup({}));
  } else {
    const { init } = await import("./dist/index.js");
    await init({});
  }
  return globalThis.__EmoExports;
}
const core = await instantiateCore();

// @litertjs/core (LiteRT.js) is loaded once per process; its Wasm runtime files
// (node_modules/@litertjs/core/wasm/) initialize a single time. Callers can
// inject a module via `options.litert` (tests/custom builds) and override the
// Wasm directory via `options.litertWasmDir`.
async function loadLiteRtModule(options) {
  if (options.litert) return options.litert;
  try {
    return await import("@litertjs/core");
  } catch (e) {
    throw new Error(
      "@desert-ant-labs/emo: the browser build needs LiteRT.js. Install it as a peer " +
        "dependency: `npm i @desert-ant-labs/emo @litertjs/core`. " +
        "(In Node, import the package normally to use the native server-side build instead.)",
      { cause: e });
  }
}

async function resolveWasmDir(options) {
  if (options.litertWasmDir) return options.litertWasmDir;
  if (IS_NODE) {
    // Serve the runtime's own Wasm files straight from the installed package.
    const { createRequire } = await import("node:module");
    const { pathToFileURL } = await import("node:url");
    const path = await import("node:path");
    const fs = await import("node:fs");
    const require = createRequire(import.meta.url);
    // Package layout: <root>/dist/index.js and <root>/wasm/. Walk up from the
    // resolved entry to the package root, then point at wasm/.
    let dir = path.dirname(require.resolve("@litertjs/core"));
    for (let i = 0; i < 4 && !fs.existsSync(path.join(dir, "wasm")); i++) {
      dir = path.dirname(dir);
    }
    return pathToFileURL(path.join(dir, "wasm") + "/").href;
  }
  // Browser default: the jsDelivr CDN mirror of the package's wasm/ directory.
  return "https://cdn.jsdelivr.net/npm/@litertjs/core/wasm/";
}

let liteRtReady;
async function ensureLiteRt(options, lrt) {
  liteRtReady ??= lrt.loadLiteRt(await resolveWasmDir(options));
  await liteRtReady;
}

/**
 * On-device emoji suggestion. Create one with `await Emo.load(...)` and reuse
 * it, mirroring the iOS/Swift SDK.
 *
 * ```js
 * const emo = await Emo.load();                 // downloads the model on demand, cached
 * const suggestions = await emo.suggestions("Pay my bills");  // [{ emoji, confidence }, ...]
 * ```
 */
export class Emo {
  /**
   * Load the model and return a ready suggester. Download, SHA-256
   * verification, and caching are handled by the runtime; this host owns the
   * LiteRT.js session behind the generic tensor contract (createSession + run).
   * The repo and revision are pinned to the SDK.
   */
  static async load(options = {}) {
    const resolved = options;
    const lrt = await loadLiteRtModule(resolved);
    await ensureLiteRt(resolved, lrt);
    const { loadAndCompile, Tensor } = lrt;
    const accelerator = resolved.accelerator ?? "wasm";
    let model;

    // Generic tensor I/O with the WebAssembly runtime (JSInferenceSession): both
    // sides exchange { name: { data: Uint8Array, dims: number[], type } }. The
    // emo tflite takes the n-gram/semantic int32/float32 inputs and returns a
    // float32 `probabilities` tensor; LiteRT.js infers each dtype from the array.
    const typedArray = (t) => {
      const bytes = t.data.slice();  // own, aligned buffer
      switch (t.type) {
        case "int32": return new Int32Array(bytes.buffer);
        case "float32": return new Float32Array(bytes.buffer);
        case "uint8": return new Uint8Array(bytes.buffer);
        default: throw new Error(`unsupported tensor type: ${t.type}`);
      }
    };
    globalThis.__EmoHost = {
      // modelSource is the cached file path (node) or the model bytes (browser).
      createSession: async (modelSource) => {
        let modelData = modelSource;
        if (typeof modelSource === "string" && IS_NODE) {
          const fs = await import("node:fs");
          modelData = new Uint8Array(fs.readFileSync(modelSource));
        }
        model = await loadAndCompile(modelData, { accelerator });
      },
      run: async (inputs) => {
        const feeds = {};
        const made = [];
        for (const [name, t] of Object.entries(inputs)) {
          const tensor = new Tensor(typedArray(t), Array.from(t.dims));
          feeds[name] = tensor;
          made.push(tensor);
        }
        // LiteRT.js uses manual memory management: results and any GPU->wasm
        // copies must be deleted, along with the input tensors we made.
        const results = await model.run(feeds);
        const outputs = {};
        const toDelete = [...made];
        for (const [name, out] of Object.entries(results)) {
          const host = accelerator === "wasm" ? out : await out.moveTo("wasm");
          const arr = host.toTypedArray();
          outputs[name] = {
            data: new Uint8Array(arr.buffer.slice(arr.byteOffset, arr.byteOffset + arr.byteLength)),
            dims: Array.from(host.type.layout.dimensions),
            type: host.type.dtype,
          };
          toDelete.push(out);
          if (host !== out) toDelete.push(host);
        }
        for (const t of toDelete) t.delete();
        return outputs;
      },
    };

    const onProgress = typeof resolved.onProgress === "function" ? resolved.onProgress : undefined;
    if (resolved.directory == null) {
      // Emo is small, so the npm package includes the LiteRT model by default.
      // Browser bundlers understand new URL(..., import.meta.url) as a package
      // asset, and direct node_modules serving works too.
      const { metaJSON, tokenizerBytes, modelBytes } = await loadPackagedModel();
      await core.loadBundled(metaJSON, tokenizerBytes, modelBytes);
      onProgress?.(1);
    } else {
      // An explicit directory opts into adopt-or-download behavior. Base for the
      // managed nested cache (node): ~/.cache; empty (in-memory) in the browser.
      let cacheRoot = "";
      if (IS_NODE) {
        const os = await import("node:os");
        const path = await import("node:path");
        cacheRoot = path.join(os.homedir(), ".cache");
      }
      await core.load(cacheRoot, resolved.directory, onProgress);
    }
    return new Emo();
  }

  /**
   * Suggest emojis for a phrase, most likely first. Returns up to `limit`
   * `{ emoji, confidence }` suggestions; empty input returns `[]`.
   */
  async suggestions(text, options = {}) {
    const limit = options.limit ?? 3;
    const skinTone = SKIN_TONES[options.skinTone ?? "default"] ?? 0;
    return core.suggest(String(text ?? ""), limit, skinTone);
  }
}

// Read the model files the npm package ships (packages/emo-node/model): node
// reads them off disk; browser bundlers resolve new URL(..., import.meta.url)
// to the packaged assets and fetch them.
async function loadPackagedModel() {
  if (IS_NODE) {
    const fs = await import("node:fs");
    const path = await import("node:path");
    const { fileURLToPath } = await import("node:url");
    const here = path.dirname(fileURLToPath(import.meta.url));
    return {
      metaJSON: fs.readFileSync(path.join(here, "model", "emo_meta.json"), "utf8"),
      tokenizerBytes: new Uint8Array(fs.readFileSync(path.join(here, "model", "emo_tokenizer.bin"))),
      modelBytes: new Uint8Array(fs.readFileSync(path.join(here, "model", "emo.tflite"))),
    };
  }
  const [meta, tok, model] = await Promise.all([
    fetch(new URL("./model/emo_meta.json", import.meta.url)).then((r) => r.text()),
    fetch(new URL("./model/emo_tokenizer.bin", import.meta.url)).then((r) => r.arrayBuffer()),
    fetch(new URL("./model/emo.tflite", import.meta.url)).then((r) => r.arrayBuffer()),
  ]);
  return { metaJSON: meta, tokenizerBytes: new Uint8Array(tok), modelBytes: new Uint8Array(model) };
}

/** Preferred emoji skin tone for skin-tone-capable emoji. */
export type EmojiSkinTone =
  | "default"
  | "light"
  | "mediumLight"
  | "medium"
  | "mediumDark"
  | "dark";

/** A single emoji suggestion. */
export interface EmoSuggestion {
  /** The suggested emoji. */
  emoji: string;
  /** The model's normalized confidence, from `0` to `1`. */
  confidence: number;
}

/** Options for a single suggestion call. */
export interface SuggestOptions {
  /** Maximum number of suggestions to return (default `3`). */
  limit?: number;
  /** Preferred skin tone for skin-tone-capable emoji (default `"default"`). */
  skinTone?: EmojiSkinTone;
}

/**
 * How the model is loaded. By default the model is downloaded from the Hugging
 * Face Hub at the pinned revision and cached (filesystem on Node, Cache API /
 * IndexedDB in the browser). The repo and revision are pinned to the SDK. Use
 * `directory` (Node) or `modelBaseUrl` (browser) to self-host / run offline.
 */
export interface LoadOptions {
  /**
   * Adopt self-hosted model files from an explicit directory (Node) instead of
   * downloading from the Hugging Face Hub. If the folder already holds the files
   * they are used offline; otherwise the model is downloaded into it. Omit to
   * download into the managed cache (`~/.cache/desert-ant-models/...`).
   */
  directory?: string;
  /**
   * Adopt self-hosted model files from a base URL (browser) instead of
   * downloading from the Hugging Face Hub, e.g. `"/assets/emo/"`. Files are
   * fetched from `${modelBaseUrl}/<file>`; use this for offline / no-runtime-CDN
   * setups. Omit to download from the Hub and cache in Cache API / IndexedDB.
   */
  modelBaseUrl?: string;
  /** Download progress in `[0, 1]`, called during {@link Emo.load}. */
  onProgress?: (fraction: number) => void;
  /** Base directory for the managed cache (Node, server-side). Defaults to
   * `~/.cache`. Ignored in the browser. */
  cacheRoot?: string;
  /** Bring-your-own LiteRT.js module (the `@litertjs/core` namespace). Browser only. */
  litert?: unknown;
  /** URL/path to the LiteRT.js Wasm directory (defaults: installed package in
   * node, jsDelivr CDN in the browser). */
  litertWasmDir?: string;
  /** LiteRT.js accelerator: `"wasm"` (XNNPACK CPU, default), `"webgpu"`, or `"webnn"`. */
  accelerator?: "wasm" | "webgpu" | "webnn";
}

/**
 * On-device multilingual emoji suggestion for JavaScript. The same import runs
 * in the browser (WebAssembly + LiteRT.js) and server-side in Node (a prebuilt
 * native core), selected automatically by conditional exports. Create one with
 * `await Emo.load(...)` and reuse it.
 *
 * ```ts
 * const emo = await Emo.load();
 * const suggestions = await emo.suggestions("Pay my bills");   // EmoSuggestion[]
 * ```
 */
export declare class Emo {
  /**
   * Load the model and return a ready suggester. Downloads from the Hugging Face
   * Hub at the pinned revision and caches by default; pass `directory` (Node) or
   * `modelBaseUrl` (browser) to adopt self-hosted files instead.
   */
  static load(options?: LoadOptions): Promise<Emo>;
  /**
   * Suggest emojis for `text`, most likely first. Returns up to `limit`
   * suggestions; empty input returns `[]`.
   */
  suggestions(text: string, options?: SuggestOptions): Promise<EmoSuggestion[]>;
  /** Free the native handle (Node). No-op in the browser. Call when done. */
  dispose(): void;
}

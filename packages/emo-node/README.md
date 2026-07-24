# @desert-ant-labs/emo

On-device multilingual emoji suggestions for JavaScript that run in the browser and in Node. Give Emo a short task, calendar entry, note, or message and it returns ranked emoji across 23 languages. Text stays local.

One import, resolved automatically by conditional exports:

- **Browser**: a local WebAssembly pipeline with [LiteRT.js](https://www.npmjs.com/package/@litertjs/core) inference.
- **Node**: a prebuilt native core, Core ML on macOS and LiteRT on Linux. No build tools, no flags.

```bash
# Browser builds:
npm i @desert-ant-labs/emo @litertjs/core

# Node only:
npm i @desert-ant-labs/emo
```

The model is downloaded from the Hugging Face Hub on first use at the SDK's pinned tag, then cached. Nothing model-sized is shipped in the npm tarball.

```js
import { Emo } from "@desert-ant-labs/emo";

const emo = await Emo.load();
const suggestions = await emo.suggestions("Pay my bills", { limit: 3 });
// [{ emoji: "💰", confidence: 0.65 }, ...]

emo.dispose(); // Node: free the native handle. No-op in the browser.
```

## Loading the model

By default `Emo.load()` downloads this platform's model files from the Hugging Face Hub ([`desert-ant-labs/emo`](https://huggingface.co/desert-ant-labs/emo)) at the SDK's pinned tag, verifies them, and caches them. Node uses the OS cache dir. The browser uses the browser fetch cache. Node fetches the `.tflite` on Linux and the `.mlmodelc/` on macOS. The browser fetches the `.tflite` for LiteRT.js.

To self-host or run fully offline, opt out of the Hub:

- `directory` (Node): an explicit model directory. Files already there are used offline, otherwise the model is downloaded into it.
- `modelBaseUrl` (Browser): a base URL you serve the model files from, for example `"/assets/emo/"`.

`Emo.load()` also accepts:

- `cacheRoot` (Node): base directory for the managed cache, default `~/.cache`.
- `onProgress`: load or download progress callback, fraction in `[0, 1]`.
- Browser-only: `litert`, a bring-your-own `@litertjs/core` module.
- Browser-only: `litertWasmDir`, URL or path to the LiteRT.js Wasm directory.
- Browser-only: `accelerator`, one of `"wasm"`, `"webgpu"`, or `"webnn"`.
- `skinTone`: one of `"default"`, `"light"`, `"mediumLight"`, `"medium"`, `"mediumDark"`, or `"dark"` when calling `suggestions`.

## Platforms

Server-side native builds ship for linux-x64, linux-arm64, and darwin-arm64. Other Node platforms throw a clear error at `load()`. Use the Swift package or a browser for those.

## License

[Desert Ant Labs Source-Available License 1.0](./LICENSE.md): free below 100,000 monthly active devices per platform. Above that a commercial license is required. Full terms: https://license.desertant.com/1.0

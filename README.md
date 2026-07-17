# Emo

On-device multilingual emoji suggestion for Swift, Android, and JavaScript. Give
Emo a short task, calendar entry, note, or message and it returns ranked emoji.
Everything runs locally, so the text never leaves the device or browser.

A hashed script-aware n-gram stream and a small transformer over a pruned
multilingual token sequence run through one shared pipeline, written once in
Swift and compiled natively for Apple, to a `.so` for Android, and to
WebAssembly for the web.

```text
"Pay my bills"   ->   💰  💳  🧾
"犬の散歩"        ->   🐕  🐾
"go for a run"   ->   🏃 (with a skin tone: 🏃🏽)
```

- [Features](#features)
- [Swift](#swift)
- [Android](#android)
- [JavaScript and TypeScript](#javascript-and-typescript)
- [Model and caching](#model-and-caching)
- [License](#license)

## Features

- Runs fully on device or in the local runtime. The text never leaves the machine.
- Suggests from a curated vocabulary of ~800 everyday emoji (task, message, and concrete nouns).
- Supports 23 languages, including CJK, Arabic, Thai, and Hindi.
- One and the same pipeline on every platform, so results match: Core ML on Apple, LiteRT on Android and Linux, LiteRT.js in the browser.
- Small model **bundled by default** on every platform, so normal installs work fully offline; on-demand download/adopt remains available (see the opt-outs below). Inference is typically a few milliseconds.
- Optional skin tone for skin-tone-capable emoji.

## Swift

### Install

Requirements: iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+, and Swift 5.9+.

Add Emo with Swift Package Manager:

```swift
.package(url: "https://github.com/Desert-Ant-Labs/emo.git", from: "0.7.0")
```

Then add the `Emo` product to your app target. Emo is small, so the Core ML
model is **bundled by default** (via the `BundledModel` package trait) and
`EmoCoreMLResources` remains available for explicit bundle construction. To use
on-demand download or an explicit model directory instead, disable the trait:

```swift
.package(url: "https://github.com/Desert-Ant-Labs/emo.git", from: "0.7.0", traits: [])
```

With the trait disabled, `Emo()` downloads on demand and `Emo(directory:)` loads
from or downloads into your chosen directory.

### Usage

Create one `Emo` and reuse it. Construction is cheap and non-blocking; the model
loads on first use, or earlier if you call `download`.

```swift
import Emo

let emo = Emo()                             // bundled model by default, ready offline
let suggestions = try await emo.suggestions(for: "Pay my bills")
// [EmoSuggestion(emoji: "💰", confidence: ...), ...]

let best = try await emo.suggestions(for: "犬の散歩", limit: 1).first?.emoji  // "🐕"
let toned = try await emo.suggestions(for: "go for a run", limit: 1, skinTone: .medium).first?.emoji  // "🏃🏽"

let fromDir = Emo(directory: myModelDir)    // explicit directory (adopt or download)
let fromBundle = Emo(bundle: EmoCoreMLResourcesBundle.bundle)  // explicit bundled resources
```

## Android

### Install

Requirements: Android API 31+ (Kotlin, coroutines). From Maven Central:

```kotlin
implementation("ai.desertant:emo:0.7.0")
```

`ai.desertant:emo` bundles the small LiteRT model by default (a transitive
`emo-tflite-resources` dependency), so normal installs work offline. To disable
bundling and download on demand instead, exclude that transitive artifact:

```kotlin
implementation("ai.desertant:emo:0.7.0") {
    exclude(group = "ai.desertant", module = "emo-tflite-resources")
}
```

### Usage

```kotlin
import ai.desertant.emo.Emo
import ai.desertant.emo.EmojiSkinTone

val emo = Emo(context)                                  // bundled model by default, offline
val suggestions = emo.suggestions("Pay my bills")       // List<EmoSuggestion>
val toned = emo.suggestions("go for a run", limit = 1, skinTone = EmojiSkinTone.MEDIUM)
emo.close()

val fromDir = Emo(context, directory = myModelDir)      // explicit directory (adopt or download)
val bundled = Emo.bundled()                             // explicit bundled constructor
```

## JavaScript and TypeScript

One package, both environments: the same `import { Emo }` runs in the **browser**
(WebAssembly + LiteRT.js) and **server-side in Node** (a prebuilt native core),
selected automatically by conditional exports.

### Install

In Node (server-side), just the SDK - inference is native, no extra runtime:

```bash
npm install @desert-ant-labs/emo
```

In the browser, also add the LiteRT.js runtime (an optional peer dependency):

```bash
npm install @desert-ant-labs/emo @litertjs/core
```

Emo is small, so the npm package ships the model files in the tarball and
`Emo.load()` uses them by default (offline in both Node and the browser). Pass a
`directory` option to opt into adopt-or-download from the Hugging Face Hub.

### Usage

```js
import { Emo } from "@desert-ant-labs/emo";

const emo = await Emo.load();                            // bundled model by default, offline
const suggestions = await emo.suggestions("Pay my bills"); // [{ emoji, confidence }, ...]
const toned = await emo.suggestions("go for a run", { limit: 1, skinTone: "medium" });
emo.dispose();                                           // frees the native handle (Node; no-op in browser)
```

The Node build ships prebuilt natives for linux-x64, linux-arm64, and
darwin-arm64. See `Examples/EmoWasmExample` for a Node example and a
headless-Chromium browser harness.

## Model and caching

All platforms run the same weights: `emo.mlmodelc` (Core ML) on Apple and
`emo.tflite` (LiteRT) everywhere else, plus the shared `emo_meta.json` and
`emo_tokenizer.bin` sidecars. The two tokenizers (script-aware n-grams and a
pruned-unigram semantic tokenizer) run in the shared Swift core, so the exact
same fixed-window tensors feed every backend.

Emo is small, so every platform **bundles the model by default** and works
offline out of the box: the SwiftPM `BundledModel` trait, a transitive
`emo-tflite-resources` dependency on Android, and the model files shipped in the
npm tarball. Each platform also has an opt-out (a disabled trait, a Gradle
exclusion, or a `directory` option) that switches to on-demand download from the
Hugging Face Hub at [`desert-ant-labs/emo`](https://huggingface.co/desert-ant-labs/emo)
(SHA-256 verified and cached), pinned to a revision by the SDK.

## License

Source-available under the Desert Ant Labs Source-Available License 1.0. See
[LICENSE.md](LICENSE.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

#if os(WASI)
import Inference
import JavaScriptEventLoop
import JavaScriptKit
@_spi(EmoBindings) import Emo

// WebAssembly entry point. Mirrors the iOS/Swift SDK (suggestion only). The JS
// host must set `globalThis.__EmoHost` (an async LiteRT.js session + runner, see
// desert-ant-core's JSInferenceSession) before the first suggestion. After
// start, the module exposes:
//
//     globalThis.__EmoExports = {
//       load(cacheRoot, directory?, onProgress?)          -> Promise<boolean>,
//       loadBundled(metaJSON, tokenizerBytes, modelBytes) -> Promise<boolean>,
//       suggest(text, limit?, skinTone?)                  -> Promise<[{emoji, confidence}]>,
//     }
//
// `skinTone` is a number: 0 default, 1 light, 2 mediumLight, 3 medium,
// 4 mediumDark, 5 dark. `packages/emo-node` wraps this in the public typed API;
// nothing else should touch these globals.
JavaScriptEventLoop.installGlobalExecutor()

private nonisolated(unsafe) var suggester: Emo?
private func instance() throws -> Emo {
    guard let suggester else { throw EmoError.modelNotFound }
    return suggester
}

private func skinTone(_ raw: Double?) -> EmojiSkinTone {
    switch Int(raw ?? 0) {
    case 1: return .light
    case 2: return .mediumLight
    case 3: return .medium
    case 4: return .mediumDark
    case 5: return .dark
    default: return .default
    }
}

private func encode(_ suggestions: [EmoSuggestion]) -> JSValue {
    let arr = JSObject.global.Array.function!.new()
    for (i, s) in suggestions.enumerated() {
        let o = JSObject.global.Object.function!.new()
        o.emoji = .string(s.emoji)
        o.confidence = .number(s.confidence)
        arr[i] = .object(o)
    }
    return .object(arr)
}

let suggestFn = JSClosure { args in
    let text = args.first?.string ?? ""
    let limit = args.count > 1 ? Int(args[1].number ?? 3) : 3
    let tone = skinTone(args.count > 2 ? args[2].number : nil)
    return JSPromise { resolve in
        Task {
            do {
                let suggestions = try await instance().suggestions(for: text, limit: limit, skinTone: tone)
                resolve(.success(encode(suggestions)))
            } catch {
                resolve(.failure(.string(String(describing: error))))
            }
        }
    }.jsValue
}

// load(cacheRoot, directory, onProgress?): the repo and revision are pinned to
// the SDK. `cacheRoot` is the base for the managed nested cache (node `~/.cache`;
// empty in the browser). `directory`, when non-empty, is an explicit model
// directory (adopt files there, else download into it). `onProgress`, when a
// function, is called with the download fraction in [0, 1].
let loadFn = JSClosure { args in
    let cacheRoot = args.first?.string.flatMap { $0.isEmpty ? nil : $0 }
    let directory = (args.count > 1 ? args[1].string : nil).flatMap { $0.isEmpty ? nil : $0 }
    let onProgress: JSFunction? = args.count > 2 ? args[2].function : nil
    let emo = Emo(directory: directory, cacheRoot: cacheRoot)
    return JSPromise { resolve in
        Task {
            do {
                try await emo.download { fraction in
                    if let onProgress { _ = onProgress(fraction) }
                }
                suggester = emo
                resolve(.success(.boolean(true)))
            } catch {
                resolve(.failure(.string(String(describing: error))))
            }
        }
    }.jsValue
}

// loadBundled(metaJSON, tokenizerBytes, modelBytes): load the model the npm
// package ships (Emo is small, so it bundles by default). The JS host's
// createSession takes the model bytes; the sidecars come straight from the
// package, so there is no download.
private func decodeBytes(_ value: JSValue?) -> [UInt8]? {
    guard let array = value?.object, let n = array.length.number else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(Int(n))
    for i in 0..<Int(n) { bytes.append(UInt8(clamping: Int(array[i].number ?? 0))) }
    return bytes
}

let loadBundledFn = JSClosure { args in
    let metaJSON = args.first?.string
    let tokenizer = decodeBytes(args.count > 1 ? args[1] : nil)
    let modelBytes = decodeBytes(args.count > 2 ? args[2] : nil)
    return JSPromise { resolve in
        Task {
            do {
                guard let metaJSON, let tokenizer, let modelBytes else { throw EmoError.modelNotFound }
                guard let host = JSObject.global.__EmoHost.object,
                      let createSession = host.createSession.object else {
                    throw EmoError.modelNotFound
                }
                guard let promise = createSession(JSTypedArray<UInt8>(modelBytes).jsValue).object.flatMap(JSPromise.init) else {
                    throw EmoError.predictionFailed
                }
                _ = try await promise.value
                let assets = try ModelAssets(
                    metaJSON: metaJSON, tokenizer: tokenizer,
                    session: JSInferenceSession(hostGlobal: "__EmoHost"))
                let emo = Emo(assets: assets)
                try await emo.waitUntilLoaded()
                suggester = emo
                resolve(.success(.boolean(true)))
            } catch {
                resolve(.failure(.string(String(describing: error))))
            }
        }
    }.jsValue
}

let exports = JSObject.global.Object.function!.new()
exports.load = .object(loadFn)
exports.loadBundled = .object(loadBundledFn)
exports.suggest = .object(suggestFn)
JSObject.global.__EmoExports = .object(exports)
#endif

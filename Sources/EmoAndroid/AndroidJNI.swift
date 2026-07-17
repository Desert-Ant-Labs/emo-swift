#if os(Android)
import Android
import HostBridge

// JNI entry points for ai.desertant.emo.EmoNative, written directly in Swift
// (no C shim). The reusable harness (byte marshalling, thread attach, and
// installing the CHostBridge JSON/HTTP callbacks against the host class) lives
// in desert-ant-core's HostBridge module; this file forwards to the C ABI in
// CABI.swift. The API mirrors the Swift SDK: an instance (opaque handle) per
// Emo, with lazy loading, isDownloaded, download, and run.
//
// The model is either bundled (createBundled, bytes from the optional
// emo-tflite-resources) or loaded on demand (create, download/local dir). The
// phrase crosses as a UTF-8 byte array; suggestions come back as the FFIBuffer
// length-prefixed typed buffer. Handles cross as jlong.

private func handle(_ ptr: UnsafeMutableRawPointer?) -> jlong { jlong(Int(bitPattern: ptr)) }
private func pointer(_ handle: jlong) -> UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: Int(handle)) }

/// Create a suggester. `cacheRoot` is the app cache dir (base for the managed
/// nested layout); `directory` is an explicit model dir (direct) or NULL/empty
/// for the managed layout under `cacheRoot`.
@_cdecl("Java_ai_desertant_emo_EmoNative_create")
public func EmoNative_create(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?,
                             _ cacheRoot: jbyteArray?, _ directory: jbyteArray?) -> jlong {
    installHostBridge(env, cls)  // wires JSON + http callbacks to EmoNative's statics
    let root = hostCopyBytes(env, cacheRoot).flatMap { $0.isEmpty ? nil : Array($0) }
    let dir = hostCopyBytes(env, directory).flatMap { $0.isEmpty ? nil : Array($0) }
    return withHostCText(root) { rootPtr in
        withHostCText(dir) { dirPtr in handle(emo_create(rootPtr, dirPtr)) }
    }
}

/// Create a suggester from bundled model bytes (the emo-tflite-resources path).
@_cdecl("Java_ai_desertant_emo_EmoNative_createBundled")
public func EmoNative_createBundled(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?,
                                    _ metaJson: jbyteArray?, _ tokenizer: jbyteArray?,
                                    _ model: jbyteArray?) -> jlong {
    installHostBridge(env, cls)
    guard let meta = hostCopyBytes(env, metaJson), let tok = hostCopyBytes(env, tokenizer),
          let mdl = hostCopyBytes(env, model) else { return 0 }
    return withHostCText(meta) { metaC in
        tok.withUnsafeBufferPointer { t in
            mdl.withUnsafeBufferPointer { m in
                handle(emo_create_bundled(metaC, t.baseAddress, Int32(t.count), m.baseAddress, Int32(m.count)))
            }
        }
    }
}

@_cdecl("Java_ai_desertant_emo_EmoNative_destroy")
public func EmoNative_destroy(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?, _ handle: jlong) {
    emo_destroy(pointer(handle))
}

@_cdecl("Java_ai_desertant_emo_EmoNative_isDownloaded")
public func EmoNative_isDownloaded(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?, _ handle: jlong) -> jint {
    installHostBridge(env, cls)
    return jint(emo_is_downloaded(pointer(handle)))
}

/// Download/verify the model ahead of time. Blocking; call off the main thread.
@_cdecl("Java_ai_desertant_emo_EmoNative_download")
public func EmoNative_download(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?, _ handle: jlong) -> jint {
    installHostBridge(env, cls)
    return jint(emo_download(pointer(handle)))
}

/// Suggest emojis for a phrase. `text` is a UTF-8 byte array.
@_cdecl("Java_ai_desertant_emo_EmoNative_run")
public func EmoNative_run(_ env: UnsafeMutablePointer<JNIEnv?>, _ cls: jclass?,
                          _ handle: jlong, _ text: jbyteArray?,
                          _ limit: jint, _ skinTone: jint) -> jbyteArray? {
    installHostBridge(env, cls)
    guard let bytes = hostCopyBytes(env, text) else { return nil }
    var utf8 = bytes
    utf8.append(0)  // NUL-terminate for String(cString:)
    let buf = utf8.withUnsafeBufferPointer { p in
        p.baseAddress!.withMemoryRebound(to: CChar.self, capacity: p.count) { c in
            emo_run(pointer(handle), c, Int32(limit), Int32(skinTone))
        }
    }
    return hostTakeBuffer(env, buf)
}
#endif

import Foundation

/// Bundle accessor for LiteRT resources only. Used by Linux and Windows builds
/// (Android bundles the optional `:emo-tflite-resources` Gradle artifact, and
/// wasm always downloads); Apple platforms use `EmoCoreMLResources` instead.
///
/// ```swift
/// import EmoTFLiteResources
/// let emo = Emo(bundle: EmoTFLiteResourcesBundle.bundle)
/// ```
public enum EmoTFLiteResourcesBundle {
    public static var bundle: Bundle { Bundle.module }
}

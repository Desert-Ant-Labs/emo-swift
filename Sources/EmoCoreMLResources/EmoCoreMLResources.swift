import Foundation

/// Bundle accessor for Apple/Core ML resources only. This target deliberately
/// excludes `emo.tflite` so iOS/macOS apps do not ship an unused LiteRT model.
///
/// ```swift
/// import EmoCoreMLResources
/// let emo = Emo(bundle: EmoCoreMLResourcesBundle.bundle)
/// ```
public enum EmoCoreMLResourcesBundle {
    public static var bundle: Bundle { Bundle.module }
}

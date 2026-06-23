import CoreML
import Foundation

/// A single emoji suggestion returned by ``Emo/suggestions(for:limit:)``.
public struct EmoSuggestion: Identifiable, Sendable, Equatable {
    init(emoji: String, confidence: Double) {
        id = emoji
        self.emoji = emoji
        self.confidence = confidence
    }

    /// A stable identifier for this suggestion. This is the same value as ``emoji``.
    public let id: String

    /// The suggested emoji.
    public let emoji: String

    /// The model's normalized confidence for this suggestion, from `0...1`.
    public let confidence: Double
}

/// Errors that can occur while loading or running the bundled emoji model.
public enum EmoError: Error, LocalizedError, Sendable {
    /// A bundled resource (model, tokenizer, or metadata) could not be found.
    case modelNotFound

    /// Core ML prediction failed or returned an unexpected output.
    case predictionFailed

    public var errorDescription: String? {
        switch self {
        case .modelNotFound: "An Emo model resource was not found in the package bundle."
        case .predictionFailed: "Emoji prediction failed."
        }
    }
}

/// Predicts emojis for short task, calendar, or message text.
///
/// Emo runs fully on-device using a small bundled Core ML model (~3.2 MB) plus a
/// ~0.55 MB tokenizer, across 22 languages.
///
/// ```swift
/// let suggestions = try await Emo.suggestions(for: "Pay my bills")
/// let emoji = try await Emo.suggestions(for: "犬の散歩", limit: 1).first?.emoji  // "🐕"
/// let toned = try await Emo.suggestions(for: "go for a run", limit: 1, skinTone: .medium).first?.emoji  // "🏃🏽"
/// ```
public enum Emo {
    /// Returns emoji suggestions for a phrase, sorted from most to least likely.
    ///
    /// - Parameters:
    ///   - text: A short task, calendar entry, note, or message draft.
    ///   - limit: The maximum number of suggestions to return. Pass `1` for only the best emoji.
    ///   - skinTone: Preferred skin tone for skin-tone-capable emoji. Defaults to ``EmojiSkinTone/default``.
    /// - Returns: Up to `limit` emoji suggestions. Empty input returns an empty array.
    public static func suggestions(for text: String, limit: Int = 3, skinTone: EmojiSkinTone = .default) async throws -> [EmoSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let loaded = try await modelTask.value
        let cfg = loaded.cfg

        let (buckets, signs, importance) = NGram.encode(
            trimmed, nBuckets: UInt32(cfg.nBuckets), nHashes: cfg.nHashes,
            nImportance: UInt32(cfg.nImportance), maxFeatures: maxLen)
        let featureCount = buckets.count

        var sem = loaded.sem.encode(trimmed)
        if sem.count > maxLen { sem = Array(sem.prefix(maxLen)) }
        if sem.isEmpty { sem = [Int32(cfg.semPadIndex)] }

        guard
            let mlBuckets = try? MLMultiArray(shape: [featureCount as NSNumber, cfg.nHashes as NSNumber], dataType: .int32),
            let mlSigns = try? MLMultiArray(shape: [featureCount as NSNumber, cfg.nHashes as NSNumber], dataType: .float32),
            let mlImp = try? MLMultiArray(shape: [featureCount as NSNumber], dataType: .int32),
            let mlNgramCount = try? MLMultiArray(shape: [1], dataType: .float32),
            let mlSem = try? MLMultiArray(shape: [sem.count as NSNumber], dataType: .int32),
            let mlSemCount = try? MLMultiArray(shape: [1], dataType: .float32)
        else { throw EmoError.predictionFailed }

        let bPtr = mlBuckets.dataPointer.bindMemory(to: Int32.self, capacity: featureCount * cfg.nHashes)
        let sPtr = mlSigns.dataPointer.bindMemory(to: Float.self, capacity: featureCount * cfg.nHashes)
        let iPtr = mlImp.dataPointer.bindMemory(to: Int32.self, capacity: featureCount)
        for f in 0..<featureCount {
            iPtr[f] = importance[f]
            for k in 0..<cfg.nHashes {
                bPtr[f * cfg.nHashes + k] = buckets[f][k]
                sPtr[f * cfg.nHashes + k] = signs[f][k]
            }
        }
        mlNgramCount[0] = NSNumber(value: Float(featureCount))
        let semPtr = mlSem.dataPointer.bindMemory(to: Int32.self, capacity: sem.count)
        for i in sem.indices { semPtr[i] = sem[i] }
        mlSemCount[0] = NSNumber(value: Float(sem.count))

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "ngram_buckets": mlBuckets, "ngram_signs": mlSigns, "ngram_importance": mlImp,
            "ngram_count": mlNgramCount, "sem_ids": mlSem, "sem_count": mlSemCount,
        ]) else { throw EmoError.predictionFailed }

        let output: MLFeatureProvider = if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
            try await loaded.model.prediction(from: provider)
        } else {
            try loaded.model.prediction(from: provider)
        }

        guard let raw = output.featureValue(for: "classLabel_probs")?.dictionaryValue else {
            throw EmoError.predictionFailed
        }
        var probs: [(String, Double)] = []
        probs.reserveCapacity(raw.count)
        for (key, value) in raw {
            if let emoji = key as? String { probs.append((emoji, value.doubleValue)) }
        }
        return probs
            .sorted { $0.1 > $1.1 }
            .prefix(max(0, limit))
            .map { EmoSuggestion(emoji: $0.0.applyingSkinTone(skinTone), confidence: $0.1) }
    }

    private struct Config: Decodable {
        let nHashes: Int
        let nBuckets: Int
        let nImportance: Int
        let semPadIndex: Int

        enum CodingKeys: String, CodingKey {
            case nHashes = "n_hashes", nBuckets = "n_buckets"
            case nImportance = "n_importance", semPadIndex = "sem_pad_index"
        }
    }

    private struct Loaded { let model: MLModel; let sem: SemTokenizer; let cfg: Config }

    private static let maxLen = 1024

    private static let modelTask = Task<Loaded, Error> {
        guard
            let modelURL = Bundle.module.url(forResource: "Emo", withExtension: "mlmodelc"),
            let metaURL = Bundle.module.url(forResource: "emo_meta", withExtension: "json"),
            let tokURL = Bundle.module.url(forResource: "emo_tokenizer", withExtension: "bin")
        else { throw EmoError.modelNotFound }

        let config = MLModelConfiguration()
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly
        #else
        config.computeUnits = .all
        #endif

        let model = try await MLModel.load(contentsOf: modelURL, configuration: config)
        let cfg = try JSONDecoder().decode(Config.self, from: Data(contentsOf: metaURL))
        guard let sem = SemTokenizer(data: try Data(contentsOf: tokURL)) else {
            throw EmoError.modelNotFound
        }
        return Loaded(model: model, sem: sem, cfg: cfg)
    }
}

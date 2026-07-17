import Foundation
import XCTest
@testable import Emo

#if canImport(CoreML)
import EmoCoreMLResources
#elseif os(Linux) || os(Windows)
import EmoTFLiteResources
#endif

/// End-to-end suggestion through the bundled model. On Apple this runs the Core
/// ML artifact; on Linux/Windows the LiteRT artifact (via LiteRT). Both exports
/// come from the same checkpoint and share one fixed-window signature, so the
/// results match.
final class EmoTests: XCTestCase {
    private func makeEmo() -> Emo {
        #if canImport(CoreML)
        return Emo(bundle: EmoCoreMLResourcesBundle.bundle)
        #elseif os(Linux) || os(Windows)
        return Emo(bundle: EmoTFLiteResourcesBundle.bundle)
        #else
        fatalError("no bundled model for this platform")
        #endif
    }

    private func top(_ text: String) async throws -> String {
        try await makeEmo().suggestions(for: text, limit: 1).first?.emoji ?? ""
    }

    func testEnglishPredictions() async throws {
        let emo = makeEmo()
        let bills = try await emo.suggestions(for: "Pay my bills", limit: 5).map(\.emoji)
        XCTAssertTrue(bills.contains { ["💰", "💳", "🧾", "🏦", "📄"].contains($0) }, "got \(bills)")
        let dog = try await emo.suggestions(for: "walk the dog", limit: 5).map(\.emoji)
        XCTAssertTrue(dog.contains { ["🐕", "🐾", "🚶"].contains($0) }, "got \(dog)")
        let flight = try await emo.suggestions(for: "book a flight to Tokyo", limit: 5).map(\.emoji)
        XCTAssertTrue(flight.contains("✈️"), "got \(flight)")
    }

    func testMultilingualPredictions() async throws {
        let emo = makeEmo()
        let walk = try await emo.suggestions(for: "犬の散歩", limit: 5).map(\.emoji)
        XCTAssertTrue(walk.contains { ["🐕", "🐾"].contains($0) }, "got \(walk)")
        let coffee = try await emo.suggestions(for: "café con leche", limit: 5).map(\.emoji)
        XCTAssertTrue(coffee.contains { ["☕", "🍵", "🥛"].contains($0) }, "got \(coffee)")
    }

    func testRanking() async throws {
        let results = try await makeEmo().suggestions(for: "Pay my bills", limit: 3)
        XCTAssertEqual(results.count, 3)
        XCTAssertGreaterThanOrEqual(results[0].confidence, results[1].confidence)
        XCTAssertTrue(results.allSatisfy { (0...1).contains($0.confidence) })
    }

    func testEmptyInput() async throws {
        let results = try await makeEmo().suggestions(for: "   ")
        XCTAssertTrue(results.isEmpty)
    }

    /// The default `Emo()` (no bundle argument) uses the model bundled into the
    /// SDK by the BundledModel trait - available offline, no download.
    func testDefaultInitUsesBundledModel() async throws {
        let emo = Emo()
        XCTAssertTrue(emo.isDownloaded())
        let results = try await emo.suggestions(for: "Pay my bills", limit: 3)
        XCTAssertEqual(results.count, 3)
    }

    func testSkinTonePostprocessing() {
        XCTAssertEqual("🏃".applyingSkinTone(.medium), "🏃🏽")
        XCTAssertEqual("🧑‍🍳".applyingSkinTone(.dark), "🧑🏿‍🍳")
        XCTAssertEqual("✍️".applyingSkinTone(.light), "✍🏻")
        XCTAssertEqual("🐕".applyingSkinTone(.medium), "🐕")
    }
}

@testable import Emo
import Testing

struct EmoTests {
    private func top(_ task: String) async throws -> String {
        try await Emo.suggestions(for: task, limit: 1).first?.emoji ?? ""
    }

    @Test func englishPredictions() async throws {
        #expect(["💰", "💳", "🧾", "🏦"].contains(try await top("Pay my bills")))
        #expect(["🐕", "🐾", "🚶"].contains(try await top("walk the dog")))
        #expect(try await top("book a flight to Tokyo") == "✈️")
        #expect(["🦷", "📅", "🏥"].contains(try await top("dentist appointment")))
    }

    @Test func multilingualPredictions() async throws {
        #expect(["🐕", "🐾"].contains(try await top("犬の散歩")))
        #expect(["☕", "🍵", "🥛"].contains(try await top("café con leche")))
        #expect(try await top("réserver un vol pour Tokyo") == "✈️")
    }

    @Test func ranking() async throws {
        let results = try await Emo.suggestions(for: "Pay my bills", limit: 3)
        #expect(results.count == 3)
        #expect(results[0].confidence >= results[1].confidence)
        #expect(results.allSatisfy { (0...1).contains($0.confidence) })
    }

    @Test func emptyInput() async throws {
        #expect(try await Emo.suggestions(for: "   ").isEmpty)
    }

    @Test func skinTonePostprocessing() {
        #expect("🏃".applyingSkinTone(.medium) == "🏃🏽")
        #expect("🧑‍🍳".applyingSkinTone(.dark) == "🧑🏿‍🍳")
        #expect("✍️".applyingSkinTone(.light) == "✍🏻")
        #expect("🐕".applyingSkinTone(.medium) == "🐕")
    }
}

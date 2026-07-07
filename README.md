Emo is a small on-device Swift package that suggests emojis for short tasks, calendar entries, or phrases.

```swift
import Emo

let suggestions = try await Emo.suggestions(for: "Pay my bills")
// ["💰", "💳", "🧾", ...]

let emoji = try await Emo.suggestions(for: "犬の散歩", limit: 1).first?.emoji
// "🐕"

let toned = try await Emo.suggestions(for: "go for a run", limit: 1, skinTone: .medium).first?.emoji
// "🏃🏽"
```

## Features

- Runs fully on-device using Core ML
- Suggests from a curated vocabulary of ~800 everyday emojis (task, message, and concrete nouns)
- Supports 23 languages (incl. CJK, Arabic, Thai, Hindi, …)
- Bundled model + tokenizer are about 5.0 MB
- Prediction is typically well under 2 ms on modern iPhones
- No network access required

## Installation

Add this package to your app with Swift Package Manager.

```swift
.package(url: "https://github.com/Desert-Ant-Labs/emo-swift.git", from: "0.3.0")
```

Then add the `Emo` product to your app target.

## Usage

```swift
import Emo

let results = try await Emo.suggestions(for: "Call mom")

for result in results {
    print(result.emoji, result.confidence)
}
```

Limit the number of returned suggestions:

```swift
let best = try await Emo.suggestions(for: "bike to work", limit: 1).first?.emoji
```

## API

```swift
public enum Emo {
    public static func suggestions(
        for text: String,
        limit: Int = 3,
        skinTone: EmojiSkinTone = .default
    ) async throws -> [EmoSuggestion]
}

public enum EmojiSkinTone: Sendable, Equatable {
    case `default`, light, mediumLight, medium, mediumDark, dark
}

public struct EmoSuggestion: Identifiable, Sendable, Equatable {
    public let id: String
    public let emoji: String
    public let confidence: Double
}
```

## Example App

A minimal example app is included in `Examples/EmoExample`.

## Model

The bundled model is published at [`desert-ant-labs/emo`](https://huggingface.co/desert-ant-labs/emo) on Hugging Face: full weights, the compiled Core ML build, and the model card.

## License

[Desert Ant Labs Source-Available License](https://license.desertant.ai/1.0). Free for
most apps; a commercial license is required at scale. Full terms are at the link.
Licensing: <licensing@desertant.ai>.

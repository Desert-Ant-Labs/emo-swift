// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Emo",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Emo", targets: ["Emo"]),
    ],
    targets: [
        .target(
            name: "Emo",
            resources: [
                .copy("Resources/Emo.mlmodelc"),
                .copy("Resources/emo_tokenizer.bin"),
                .copy("Resources/emo_meta.json"),
            ]
        ),
        .testTarget(
            name: "EmoTests",
            dependencies: ["Emo"]
        ),
    ]
)

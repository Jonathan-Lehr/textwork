// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TextworkEditor",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "TextworkEditor", targets: ["TextworkEditor"]),
        .library(name: "TextworkHighlightOracle", targets: ["TextworkHighlightOracle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
    ],
    targets: [
        .target(name: "TextworkEditor"),
        .target(
            name: "TextworkHighlightOracle",
            dependencies: [
                "TextworkEditor",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .executableTarget(
            name: "TextworkEditorBench",
            dependencies: [
                "TextworkEditor",
                "TextworkHighlightOracle",
            ]
        ),
        .testTarget(
            name: "TextworkEditorTests",
            dependencies: ["TextworkEditor"]
        ),
        .testTarget(
            name: "TextworkHighlightOracleTests",
            dependencies: ["TextworkHighlightOracle"]
        ),
    ]
)

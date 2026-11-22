import Foundation

struct Host: Codable {
    var operatingSystem: String
    var processorCount: Int
    var swiftVersion: String
}

struct Timing: Codable {
    var utf8Bytes: Int
    var iterations: Int
    var medianMilliseconds: Double
    var percentile95Milliseconds: Double
}

struct HandRolledResult: Codable {
    var documentUTF8Bytes: Int
    var fullHighlight: Timing
    var incrementalKeystrokeAtMiddle: Timing
    var blocksReparsedForMiddleKeystroke: Int
    var blocksReusedForMiddleKeystroke: Int
    var blockCount: Int
}

struct SwiftMarkdownResult: Codable {
    var documentUTF8Bytes: Int
    var fullHighlight: Timing
    var note: String
}

struct AttributedStringResult: Codable {
    var documentUTF8Bytes: Int
    var fullConversion: Timing
    var renderedCharacterCount: Int
    var sourceCharacterCount: Int
    var note: String
}

struct AttributeApplyResult: Codable {
    var documentUTF8Bytes: Int
    var applyAllSpans: Timing
    var applyInvalidatedRange: Timing
    var invalidatedUTF16Length: Int
    var note: String
}

struct Report: Codable {
    var host: Host
    var documentShape: String
    var handRolled: [HandRolledResult]
    var swiftMarkdown: [SwiftMarkdownResult]
    var attributedStringMarkdown: [AttributedStringResult]
    var appKitAttributeApply: [AttributeApplyResult]
    var treeSitter: String
}

import Foundation
import TextworkEditor
import TextworkHighlightOracle
#if canImport(AppKit)
import AppKit
#endif

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

let targetBytes = [10_000, 100_000, 1_000_000]
let handRolled = MarkdownHighlighter()
let swiftMarkdown = SwiftMarkdownHighlighter()

var handRolledResults: [HandRolledResult] = []
var swiftMarkdownResults: [SwiftMarkdownResult] = []
var attributedResults: [AttributedStringResult] = []
var applyResults: [AttributeApplyResult] = []

for bytes in targetBytes {
    let text = makeDocument(utf8ByteCount: bytes)
    let actualBytes = text.utf8.count
    let iterations = bytes >= 1_000_000 ? 9 : 15

    _ = handRolled.highlight(text)
    let full = measure(iterations) { _ = handRolled.highlight(text) }
    let baseline = handRolled.highlight(text)
    let midpoint = text.utf16.count / 2
    let edit = MarkdownEdit(range: midpoint..<midpoint, replacement: "Z")
    _ = handRolled.apply(edit, to: baseline)
    let incremental = measure(iterations) { _ = handRolled.apply(edit, to: baseline) }
    let once = handRolled.apply(edit, to: baseline)
    handRolledResults.append(
        HandRolledResult(
            documentUTF8Bytes: actualBytes,
            fullHighlight: Timing(utf8Bytes: actualBytes, iterations: iterations, medianMilliseconds: full.median, percentile95Milliseconds: full.p95),
            incrementalKeystrokeAtMiddle: Timing(utf8Bytes: actualBytes, iterations: iterations, medianMilliseconds: incremental.median, percentile95Milliseconds: incremental.p95),
            blocksReparsedForMiddleKeystroke: once.statistics.blocksReparsed,
            blocksReusedForMiddleKeystroke: once.statistics.blocksReused,
            blockCount: once.statistics.blockCount
        )
    )

    _ = swiftMarkdown.highlight(text)
    let parsed = measure(iterations) { _ = swiftMarkdown.highlight(text) }
    swiftMarkdownResults.append(
        SwiftMarkdownResult(
            documentUTF8Bytes: actualBytes,
            fullHighlight: Timing(utf8Bytes: actualBytes, iterations: iterations, medianMilliseconds: parsed.median, percentile95Milliseconds: parsed.p95),
            note: "swift-markdown reparses the whole document. This is the per-keystroke cost if it drove live highlighting. It has no incremental edit API."
        )
    )

    #if os(macOS) || os(iOS)
    attributedResults.append(measureAttributedString(text: text, iterations: min(iterations, 9)))
    #endif

    #if canImport(AppKit)
    let spans = baseline.spans
    applyResults.append(measureAttributeApply(text: text, spans: spans, iterations: min(iterations, 9)))
    #endif
}

let report = Report(
    host: Host(
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        processorCount: ProcessInfo.processInfo.processorCount,
        swiftVersion: swiftVersion()
    ),
    documentShape: "Repeated sections that include a hash heading, emphasis, strong, code span, link, image, quote, list, table, and fenced code block. Trimmed on a newline near the target size. Not one giant paragraph.",
    handRolled: handRolledResults,
    swiftMarkdown: swiftMarkdownResults,
    attributedStringMarkdown: attributedResults,
    appKitAttributeApply: applyResults,
    treeSitter: "Not measured. No tree-sitter package is linked. See docs/spikes/highlighting.md."
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(report)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))

func makeDocument(utf8ByteCount: Int) -> String {
    let section = """
    # Heading

    A paragraph with *emphasis*, **strong**, and `code` plus a [link](https://example.com) and an image ![Alt](images/figure.png).

    > A quoted line with *nested* emphasis.

    - item one
    - item two with `code`

    | Syntax | Shown |
    | --- | --- |
    | raw | live |

    ```swift
    let answer = 42
    ```

    """
    var text = ""
    while text.utf8.count < utf8ByteCount {
        text += section
    }
    if text.utf8.count == utf8ByteCount { return text }
    let utf8 = text.utf8
    let limit = utf8.index(utf8.startIndex, offsetBy: utf8ByteCount)
    guard let stringLimit = String.Index(limit, within: text) else { return text }
    if let newline = text[..<stringLimit].lastIndex(of: "\n") {
        return String(text[...newline])
    }
    return String(text[..<stringLimit])
}

func measure(_ iterations: Int, _ body: () -> Void) -> (median: Double, p95: Double) {
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let start = ContinuousClock.now
        body()
        samples.append(milliseconds(ContinuousClock.now - start))
    }
    samples.sort()
    let median = samples[samples.count / 2]
    let p95Index = min(samples.count - 1, Int((Double(samples.count) * 0.95).rounded(.up)) - 1)
    return (median, samples[max(0, p95Index)])
}

func milliseconds(_ duration: Duration) -> Double {
    let seconds = Double(duration.components.seconds) * 1000
    let attoseconds = Double(duration.components.attoseconds) / 1_000_000_000_000_000
    return seconds + attoseconds
}

func swiftVersion() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "--version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return "unavailable (\(error.localizedDescription))"
    }
}

#if os(macOS) || os(iOS)
func measureAttributedString(text: String, iterations: Int) -> AttributedStringResult {
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .full,
        failurePolicy: .returnPartiallyParsedIfPossible
    )
    _ = try? AttributedString(markdown: text, options: options)
    let timing = measure(iterations) { _ = try? AttributedString(markdown: text, options: options) }
    let rendered = (try? AttributedString(markdown: text, options: options)).map { String($0.characters) } ?? ""
    return AttributedStringResult(
        documentUTF8Bytes: text.utf8.count,
        fullConversion: Timing(utf8Bytes: text.utf8.count, iterations: iterations, medianMilliseconds: timing.median, percentile95Milliseconds: timing.p95),
        renderedCharacterCount: rendered.count,
        sourceCharacterCount: text.count,
        note: "Foundation AttributedString(markdown:) builds rendered text and drops Markdown markers. It is not a raw-source highlighter. Source-position attributes point at rendered content, not at the marker characters."
    )
}
#endif

#if canImport(AppKit)
func measureAttributeApply(text: String, spans: [HighlightSpan], iterations: Int) -> AttributeApplyResult {
    let storage = NSTextStorage(string: text)
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let color = NSColor.labelColor
    func apply() {
        let range = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: color], range: range)
        for span in spans {
            let spanRange = NSRange(location: span.startUTF16, length: span.endUTF16 - span.startUTF16)
            guard NSMaxRange(spanRange) <= storage.length else { continue }
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: spanRange)
        }
        storage.endEditing()
    }
    apply()
    let timing = measure(iterations, apply)
    return AttributeApplyResult(
        documentUTF8Bytes: text.utf8.count,
        applyAllSpans: Timing(utf8Bytes: text.utf8.count, iterations: iterations, medianMilliseconds: timing.median, percentile95Milliseconds: timing.p95),
        note: "AppKit NSTextStorage attribute replacement for every span, separate from parsing. The editor prototype paints the whole buffer after each edit."
    )
}
#endif

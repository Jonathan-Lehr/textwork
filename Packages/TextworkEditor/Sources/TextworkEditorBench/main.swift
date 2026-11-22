import Foundation
import TextworkEditor
import TextworkHighlightOracle

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
            fullHighlight: Timing(utf8Bytes: actualBytes, iterations: iterations, medianMilliseconds: full.median, percentile95Milliseconds: full.percentile95),
            incrementalKeystrokeAtMiddle: Timing(utf8Bytes: actualBytes, iterations: iterations, medianMilliseconds: incremental.median, percentile95Milliseconds: incremental.percentile95),
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
            fullHighlight: Timing(utf8Bytes: actualBytes, iterations: iterations, medianMilliseconds: parsed.median, percentile95Milliseconds: parsed.percentile95),
            note: "swift-markdown reparses the whole document. This is the per-keystroke cost if it drove live highlighting. It has no incremental edit API."
        )
    )

    #if os(macOS) || os(iOS)
    attributedResults.append(measureAttributedString(text: text, iterations: min(iterations, 9)))
    #endif

    #if canImport(AppKit)
    applyResults.append(
        measureAttributeApply(
            originalText: text,
            originalSpans: baseline.spans,
            updatedText: textByApplyingMiddleInsert(text),
            updatedSpans: once.spans,
            invalidatedRanges: once.invalidatedUTF16Ranges,
            iterations: min(iterations, 9)
        )
    )
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

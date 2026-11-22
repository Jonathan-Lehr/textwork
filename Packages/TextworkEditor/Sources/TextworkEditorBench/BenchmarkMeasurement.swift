import Foundation
import TextworkEditor
#if canImport(AppKit)
import AppKit
#endif

func measure(_ iterations: Int, _ body: () -> Void) -> (median: Double, percentile95: Double) {
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let start = ContinuousClock.now
        body()
        samples.append(milliseconds(ContinuousClock.now - start))
    }
    samples.sort()
    let median = samples[samples.count / 2]
    let percentile95Index = min(samples.count - 1, Int((Double(samples.count) * 0.95).rounded(.up)) - 1)
    return (median, samples[max(0, percentile95Index)])
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
        fullConversion: Timing(utf8Bytes: text.utf8.count, iterations: iterations, medianMilliseconds: timing.median, percentile95Milliseconds: timing.percentile95),
        renderedCharacterCount: rendered.count,
        sourceCharacterCount: text.count,
        note: "Foundation AttributedString(markdown:) builds rendered text and drops Markdown markers. It is not a raw-source highlighter. Source-position attributes point at rendered content, not at the marker characters."
    )
}
#endif

#if canImport(AppKit)
func measureAttributeApply(
    originalText: String,
    originalSpans: [HighlightSpan],
    updatedText: String,
    updatedSpans: [HighlightSpan],
    invalidatedRanges: [Range<Int>],
    iterations: Int
) -> AttributeApplyResult {
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let color = NSColor.labelColor
    let storage = NSTextStorage(string: originalText)
    func apply(to storage: NSTextStorage, spans: [HighlightSpan], ranges: [Range<Int>]?) {
        let limits = ranges ?? [0..<storage.length]
        storage.beginEditing()
        for limit in limits {
            let lower = max(0, limit.lowerBound)
            let upper = min(storage.length, limit.upperBound)
            guard upper > lower else { continue }
            storage.setAttributes(
                [.font: font, .foregroundColor: color],
                range: NSRange(location: lower, length: upper - lower)
            )
        }
        for span in spans {
            if let ranges, !ranges.contains(where: { $0.lowerBound < span.endUTF16 && span.startUTF16 < $0.upperBound }) {
                continue
            }
            let lower = max(0, span.startUTF16)
            let upper = min(storage.length, span.endUTF16)
            guard upper > lower else { continue }
            storage.addAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor,
                range: NSRange(location: lower, length: upper - lower)
            )
        }
        storage.endEditing()
    }
    apply(to: storage, spans: originalSpans, ranges: nil)
    let full = measure(iterations) { apply(to: storage, spans: originalSpans, ranges: nil) }
    let updatedStorage = NSTextStorage(string: updatedText)
    apply(to: updatedStorage, spans: updatedSpans, ranges: nil)
    let partial = measure(iterations) {
        apply(to: updatedStorage, spans: updatedSpans, ranges: invalidatedRanges)
    }
    let invalidatedLength = invalidatedRanges.reduce(0) { $0 + $1.count }
    return AttributeApplyResult(
        documentUTF8Bytes: originalText.utf8.count,
        applyAllSpans: Timing(
            utf8Bytes: originalText.utf8.count,
            iterations: iterations,
            medianMilliseconds: full.median,
            percentile95Milliseconds: full.percentile95
        ),
        applyInvalidatedRange: Timing(
            utf8Bytes: updatedText.utf8.count,
            iterations: iterations,
            medianMilliseconds: partial.median,
            percentile95Milliseconds: partial.percentile95
        ),
        invalidatedUTF16Length: invalidatedLength,
        note: "applyAllSpans replaces attributes for every span. applyInvalidatedRange is the editor path: base attributes and the spans that intersect the restyled blocks plus the inserted characters. Both are AppKit NSTextStorage updates, separate from parsing."
    )
}
#endif

import Foundation

/// UTF-16 ranges the system spell checker should leave unmarked.
///
/// Inline code, fenced and indented code, URLs, and link destinations are
/// excluded. Link text, image descriptions, and reference titles stay eligible.
public enum SpellingExclusion {
    public static func ranges(in snapshot: HighlightSnapshot) -> [Range<Int>] {
        let text = NSString(string: String(decoding: snapshot.bytes, as: UTF8.self))
        var ranges: [Range<Int>] = []
        for block in snapshot.blocks {
            append(block.spans, text: text, into: &ranges)
            if block.kind == .referenceDefinition, block.startLine < snapshot.lines.count {
                appendReferenceDestination(
                    bytes: snapshot.bytes,
                    line: snapshot.lines[block.startLine],
                    into: &ranges
                )
            }
        }
        return merged(ranges)
    }

    /// `true` when `range` shares any character with an excluded range.
    public static func covers(_ range: Range<Int>, exclusions: [Range<Int>]) -> Bool {
        guard !range.isEmpty else { return false }
        return exclusions.contains { $0.overlaps(range) }
    }

    /// Drops spelling, grammar, and correction hits that touch an excluded range.
    /// Language and other checking results pass through.
    public static func includedCheckingResults(
        _ results: [NSTextCheckingResult],
        skipping exclusions: [Range<Int>]
    ) -> [NSTextCheckingResult] {
        results.filter { result in
            guard marksSpelling(result) else { return true }
            let range = result.range
            guard range.location != NSNotFound, range.length > 0 else { return true }
            let end = range.location + range.length
            guard end >= range.location else { return true }
            return !covers(range.location..<end, exclusions: exclusions)
        }
    }

    private static func append(_ spans: [HighlightSpan], text: NSString, into ranges: inout [Range<Int>]) {
        for span in spans {
            switch span.role {
            case .codeSpan, .codeBlock:
                ranges.append(span.startUTF16..<span.endUTF16)
            case .link, .image:
                ranges.append(contentsOf: linkExclusionRanges(span, text: text))
            default:
                break
            }
        }
    }

    private static func linkExclusionRanges(_ span: HighlightSpan, text: NSString) -> [Range<Int>] {
        if span.isSyntax { return syntaxTargetRanges(span, text: text) }
        if isAngleBracketLink(span, text: text) || isWebAddress(span, text: text) {
            return [span.startUTF16..<span.endUTF16]
        }
        return []
    }

    /// Link and image syntax longer than a single marker holds the destination.
    /// Inline titles after that destination stay outside the excluded range.
    private static func syntaxTargetRanges(_ span: HighlightSpan, text: NSString) -> [Range<Int>] {
        let spanRange = span.startUTF16..<span.endUTF16
        guard spanRange.count > LinkTargetMarker.length else { return [] }
        guard span.endUTF16 <= text.length else { return [spanRange] }
        let marker = substring(text, span.startUTF16..<(span.startUTF16 + LinkTargetMarker.length))
        if marker == LinkTargetMarker.reference { return [spanRange] }
        guard marker == LinkTargetMarker.inline else { return [spanRange] }
        guard let destination = inlineDestinationRange(span, text: text) else { return [spanRange] }
        guard !destination.isEmpty else { return [] }
        return [destination]
    }

    private static func inlineDestinationRange(_ span: HighlightSpan, text: NSString) -> Range<Int>? {
        let interiorStart = span.startUTF16 + LinkTargetMarker.length
        guard span.endUTF16 > interiorStart else { return nil }
        guard character(text, at: span.endUTF16 - 1) == ASCIIByte.rightParenthesis else { return nil }
        let interiorEnd = span.endUTF16 - 1
        guard interiorEnd >= interiorStart, interiorEnd <= text.length else { return nil }
        if interiorEnd == interiorStart { return interiorStart..<interiorStart }
        if character(text, at: interiorStart) == ASCIIByte.lessThan {
            let interior = substring(text, interiorStart..<interiorEnd) as NSString
            let close = interior.range(of: ">")
            guard close.location != NSNotFound, close.location > 1 else { return interiorStart..<interiorStart }
            let start = interiorStart + 1
            let end = interiorStart + close.location
            guard end > start else { return interiorStart..<interiorStart }
            return start..<end
        }
        let interior = substring(text, interiorStart..<interiorEnd) as NSString
        let whitespace = interior.rangeOfCharacter(from: .whitespacesAndNewlines)
        let destinationLength = whitespace.location == NSNotFound ? interior.length : whitespace.location
        guard destinationLength > 0 else { return interiorStart..<interiorStart }
        return interiorStart..<(interiorStart + destinationLength)
    }

    private static func isAngleBracketLink(_ span: HighlightSpan, text: NSString) -> Bool {
        guard span.role == .link, !span.isSyntax else { return false }
        guard span.startUTF16 > 0, span.endUTF16 < text.length else { return false }
        let before = character(text, at: span.startUTF16 - 1)
        let after = character(text, at: span.endUTF16)
        return before == ASCIIByte.lessThan && after == ASCIIByte.greaterThan
    }

    private static func isWebAddress(_ span: HighlightSpan, text: NSString) -> Bool {
        guard span.role == .link, !span.isSyntax, span.endUTF16 <= text.length else { return false }
        let value = substring(text, span.startUTF16..<span.endUTF16)
        guard value.hasPrefix(WebAddressPrefix.secure) || value.hasPrefix(WebAddressPrefix.insecure) else { return false }
        return value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    private static func appendReferenceDestination(bytes: [UInt8], line: TextLine, into ranges: inout [Range<Int>]) {
        guard let parsed = ReferenceDefinitionParser.parseLine(bytes: bytes, line: line) else { return }
        guard parsed.destination.upperBound > parsed.destination.lowerBound else { return }
        let start = utf16Offset(on: line, byte: parsed.destination.lowerBound, bytes: bytes)
        let end = utf16Offset(on: line, byte: parsed.destination.upperBound, bytes: bytes)
        guard end > start else { return }
        ranges.append(start..<end)
    }

    private static func utf16Offset(on line: TextLine, byte: Int, bytes: [UInt8]) -> Int {
        var byteIndex = line.byteStart
        var utf16Index = line.utf16Start
        let limit = min(byte, bytes.count)
        while byteIndex < limit {
            let (byteLength, utf16Length) = DocumentBuffer.scalarWidth(bytes, byteIndex)
            if byteLength == 0 { break }
            byteIndex += byteLength
            utf16Index += utf16Length
        }
        return utf16Index
    }

    private static func marksSpelling(_ result: NSTextCheckingResult) -> Bool {
        let type = result.resultType
        return type.contains(.spelling) || type.contains(.grammar) || type.contains(.correction)
    }

    private static func substring(_ text: NSString, _ range: Range<Int>) -> String {
        guard range.lowerBound >= 0, range.upperBound <= text.length, range.upperBound >= range.lowerBound else { return "" }
        return text.substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    private static func character(_ text: NSString, at index: Int) -> UInt8? {
        guard index >= 0, index < text.length else { return nil }
        let value = text.character(at: index)
        guard value < 0x80 else { return nil }
        return UInt8(value)
    }

    private static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        let sorted = ranges.filter { !$0.isEmpty }.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = []
        for range in sorted {
            if let last = merged.last, last.upperBound >= range.lowerBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

private enum LinkTargetMarker {
    static let inline = "]("
    static let reference = "]["
    static let length = 2
}

private enum WebAddressPrefix {
    static let secure = "https://"
    static let insecure = "http://"
}

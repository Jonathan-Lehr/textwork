enum LineKind: UInt8, Equatable, Sendable {
    case blank
    case hashHeading
    case fenceOpen
    case fenceClose
    case fenceInside
    case thematic
    case quote
    case list
    case indentedCode
    case paragraph
    case underlineMarker
    case tableRow
    case tableDelimiter
    case referenceDefinition
    case html
}

struct TextLine: Equatable, Sendable {
    var byteStart: Int
    var byteCount: Int
    var newlineByteCount: Int
    var utf16Start: Int
    var utf16Count: Int
    var newlineUTF16Count: Int
    var kind: LineKind

    var contentByteEnd: Int { byteStart + byteCount }
    var byteEnd: Int { byteStart + byteCount + newlineByteCount }
    var utf16End: Int { utf16Start + utf16Count + newlineUTF16Count }
}

enum StructureKind: Equatable, Sendable {
    case hashHeading(level: Int)
    case underlineHeading(level: Int)
    case fence
    case thematic
    case quote
    case list
    case indentedCode
    case paragraph
    case table
    case referenceDefinition
    case htmlBlock
}

struct StyledBlock: Equatable, Sendable {
    var startLine: Int
    var endLine: Int
    var kind: StructureKind
    var spans: [HighlightSpan]
    /// Normalized labels of reference-shaped links in this block, defined or not.
    ///
    /// A later edit that adds or removes one of these definitions restyles the
    /// block without walking every other block's bytes.
    var candidateLabels: [String]
}

enum DocumentBuffer {
    static func lines(in bytes: [UInt8]) -> [TextLine] {
        var result: [TextLine] = []
        result.reserveCapacity(bytes.count / 40 + 1)
        var byteIndex = 0
        var utf16 = 0
        var lineByteStart = 0
        var lineUTF16Start = 0

        while byteIndex < bytes.count {
            let byte = bytes[byteIndex]
            if byte == ASCIIByte.lineFeed || byte == ASCIIByte.carriageReturn {
                let newlineBytes = (byte == ASCIIByte.carriageReturn && byteIndex + 1 < bytes.count && bytes[byteIndex + 1] == ASCIIByte.lineFeed) ? 2 : 1
                let contentUTF16 = utf16 - lineUTF16Start
                result.append(
                    TextLine(
                        byteStart: lineByteStart,
                        byteCount: byteIndex - lineByteStart,
                        newlineByteCount: newlineBytes,
                        utf16Start: lineUTF16Start,
                        utf16Count: contentUTF16,
                        newlineUTF16Count: newlineBytes,
                        kind: .paragraph
                    )
                )
                byteIndex += newlineBytes
                utf16 += newlineBytes
                lineByteStart = byteIndex
                lineUTF16Start = utf16
                continue
            }
            let (byteLength, utf16Length) = scalarWidth(bytes, byteIndex)
            byteIndex += byteLength
            utf16 += utf16Length
        }
        if lineByteStart < bytes.count || result.isEmpty {
            result.append(
                TextLine(
                    byteStart: lineByteStart,
                    byteCount: bytes.count - lineByteStart,
                    newlineByteCount: 0,
                    utf16Start: lineUTF16Start,
                    utf16Count: utf16 - lineUTF16Start,
                    newlineUTF16Count: 0,
                    kind: .paragraph
                )
            )
        }
        return result
    }

    static func classify(_ lines: inout [TextLine], bytes: [UInt8]) {
        let count = lines.count
        var index = 0
        var inFence = false
        var fenceMarker: UInt8 = 0
        var fenceLength = 0
        var htmlEnd: HTMLBlockEnd?
        while index < count {
            if let end = htmlEnd {
                let line = lines[index]
                if end == .blankLine, isBlank(line, bytes: bytes) {
                    htmlEnd = nil
                } else {
                    lines[index].kind = .html
                    if htmlEndIsSatisfied(end, line: line, bytes: bytes) { htmlEnd = nil }
                    index += 1
                    continue
                }
            }
            if inFence {
                if fenceCloser(lines[index], bytes: bytes, marker: fenceMarker, minimum: fenceLength) {
                    lines[index].kind = .fenceClose
                    inFence = false
                } else {
                    lines[index].kind = .fenceInside
                }
                index += 1
                continue
            }
            let line = lines[index]
            if isBlank(line, bytes: bytes) {
                lines[index].kind = .blank
                index += 1
                continue
            }
            if let fence = openingFence(line, bytes: bytes) {
                lines[index].kind = .fenceOpen
                inFence = true
                fenceMarker = fence.marker
                fenceLength = fence.length
                index += 1
                continue
            }
            if isHashHeading(line, bytes: bytes) {
                lines[index].kind = .hashHeading
                index += 1
                continue
            }
            if isThematic(line, bytes: bytes) {
                lines[index].kind = .thematic
                index += 1
                continue
            }
            if isQuote(line, bytes: bytes) {
                lines[index].kind = .quote
                index += 1
                continue
            }
            if isList(line, bytes: bytes) {
                lines[index].kind = .list
                index += 1
                continue
            }
            if isIndentedCode(line, bytes: bytes) {
                lines[index].kind = .indentedCode
                index += 1
                continue
            }
            if index + 1 < count,
               containsPipe(lines[index], bytes: bytes),
               isTableDelimiter(lines[index + 1], bytes: bytes)
            {
                lines[index].kind = .tableRow
                lines[index + 1].kind = .tableDelimiter
                var cursor = index + 2
                while cursor < count,
                      !isBlank(lines[cursor], bytes: bytes),
                      containsPipe(lines[cursor], bytes: bytes),
                      !opensBlockAfterTable(lines[cursor], bytes: bytes)
                {
                    lines[cursor].kind = .tableRow
                    cursor += 1
                }
                index = cursor
                continue
            }
            let continuesParagraph = index > 0 && lines[index - 1].kind == .paragraph
            if let opener = htmlBlockOpening(line, bytes: bytes, paragraphContinuation: continuesParagraph) {
                lines[index].kind = .html
                if !htmlEndIsSatisfied(opener, line: line, bytes: bytes) { htmlEnd = opener }
                index += 1
                continue
            }
            if !continuesParagraph, ReferenceDefinitionParser.parseLine(bytes: bytes, line: line) != nil {
                lines[index].kind = .referenceDefinition
                index += 1
                continue
            }
            lines[index].kind = .paragraph
            if index + 1 < count, underlineHeadingLevel(lines[index + 1], bytes: bytes) != nil {
                lines[index + 1].kind = .underlineMarker
                index += 2
                continue
            }
            index += 1
        }
    }

    static func definedReferenceLabels(lines: [TextLine], bytes: [UInt8]) -> Set<String> {
        var labels: Set<String> = []
        for line in lines where line.kind == .referenceDefinition {
            if let parsed = ReferenceDefinitionParser.parseLine(bytes: bytes, line: line) {
                labels.insert(parsed.normalizedLabel)
            }
        }
        return labels
    }

    static func group(_ lines: [TextLine], bytes: [UInt8]) -> [(start: Int, end: Int, kind: StructureKind)] {
        var blocks: [(start: Int, end: Int, kind: StructureKind)] = []
        var index = 0
        while index < lines.count {
            switch lines[index].kind {
            case .blank: index += 1
            case .hashHeading:
                let level = hashHeadingLevel(lines[index], bytes: bytes)
                blocks.append((index, index + 1, .hashHeading(level: level)))
                index += 1
            case .fenceOpen:
                var end = index + 1
                while end < lines.count && lines[end].kind == .fenceInside {
                    end += 1
                }
                if end < lines.count && lines[end].kind == .fenceClose { end += 1 }
                blocks.append((index, end, .fence))
                index = end
            case .thematic:
                blocks.append((index, index + 1, .thematic))
                index += 1
            case .quote:
                var end = index + 1
                while end < lines.count && lines[end].kind == .quote {
                    end += 1
                }
                blocks.append((index, end, .quote))
                index = end
            case .list:
                blocks.append((index, index + 1, .list))
                index += 1
            case .indentedCode:
                var end = index + 1
                while end < lines.count && lines[end].kind == .indentedCode {
                    end += 1
                }
                blocks.append((index, end, .indentedCode))
                index = end
            case .paragraph:
                var end = index + 1
                while end < lines.count && lines[end].kind == .paragraph {
                    end += 1
                }
                if end < lines.count && lines[end].kind == .underlineMarker {
                    let level = underlineHeadingLevel(lines[end], bytes: bytes) ?? 1
                    blocks.append((index, end + 1, .underlineHeading(level: level)))
                    index = end + 1
                } else {
                    blocks.append((index, end, .paragraph))
                    index = end
                }
            case .underlineMarker:
                let level = underlineHeadingLevel(lines[index], bytes: bytes) ?? 1
                blocks.append((index, index + 1, .underlineHeading(level: level)))
                index += 1
            case .tableRow, .tableDelimiter:
                var end = index + 1
                while end < lines.count {
                    let kind = lines[end].kind
                    if kind == .tableRow || kind == .tableDelimiter {
                        end += 1
                    } else {
                        break
                    }
                }
                blocks.append((index, end, .table))
                index = end
            case .referenceDefinition:
                blocks.append((index, index + 1, .referenceDefinition))
                index += 1
            case .html:
                var end = index + 1
                while end < lines.count && lines[end].kind == .html {
                    end += 1
                }
                blocks.append((index, end, .htmlBlock))
                index = end
            case .fenceClose, .fenceInside:
                var end = index + 1
                while end < lines.count && (lines[end].kind == .fenceInside || lines[end].kind == .fenceClose) {
                    end += 1
                }
                blocks.append((index, end, .fence))
                index = end
            }
        }
        return blocks
    }

    static func hashHeadingLevel(_ line: TextLine, bytes: [UInt8]) -> Int {
        let slice = bytes[line.byteStart..<line.contentByteEnd]
        let lead = leadingWhitespace(slice)
        var index = slice.startIndex + lead.bytes
        var hashes = 0
        while index < slice.endIndex && slice[index] == ASCIIByte.hash && hashes < MarkdownScanLimit.maximumHeadingLevel {
            hashes += 1
            index += 1
        }
        return max(1, hashes)
    }

    static func byteOffset(forUTF16 target: Int, bytes: [UInt8], lines: [TextLine]) -> Int {
        if lines.isEmpty || target <= 0 { return 0 }
        var low = 0
        var high = lines.count
        while low + 1 < high {
            let mid = (low + high) / 2
            if lines[mid].utf16Start <= target {
                low = mid
            } else {
                high = mid
            }
        }
        let line = lines[low]
        if target >= line.utf16End { return bytes.count }
        var byteIndex = line.byteStart
        var utf16 = line.utf16Start
        let limit = line.byteEnd
        while byteIndex < limit && utf16 < target {
            let (byteLength, utf16Length) = scalarWidth(bytes, byteIndex)
            if utf16 + utf16Length > target { break }
            byteIndex += byteLength
            utf16 += utf16Length
        }
        return byteIndex
    }

    static func scalarWidth(_ bytes: [UInt8], _ index: Int) -> (Int, Int) {
        guard index < bytes.count else { return (0, 0) }
        let byte = bytes[index]
        if byte < UTF8LeadingByte.singleByteLimit { return (1, 1) }
        if byte & UTF8LeadingByte.twoByteMask == UTF8LeadingByte.twoBytePrefix {
            return (min(2, bytes.count - index), 1)
        }
        if byte & UTF8LeadingByte.threeByteMask == UTF8LeadingByte.threeBytePrefix {
            return (min(3, bytes.count - index), 1)
        }
        if byte & UTF8LeadingByte.fourByteMask == UTF8LeadingByte.fourBytePrefix {
            return (min(4, bytes.count - index), 2)
        }
        return (1, 1)
    }
}

struct ReferenceDefinitionParse: Equatable {
    var normalizedLabel: String
    var openingBracket: Int
    var label: Range<Int>
    var closingBracket: Int
    var colon: Int
    var destination: Range<Int>
    var destinationOpening: Int?
    var destinationClosing: Int?
    var title: Range<Int>?
    var titleOpening: Int?
    var titleClosing: Int?
}

enum ReferenceDefinitionParser {
    static func parseLine(bytes: [UInt8], line: TextLine) -> ReferenceDefinitionParse? {
        let end = line.contentByteEnd
        var index = line.byteStart
        var columns = 0
        while index < end && columns <= MarkdownScanLimit.maximumOpeningIndent {
            if bytes[index] == ASCIIByte.space {
                columns += 1
                index += 1
            } else if bytes[index] == ASCIIByte.tab {
                let next = columns + (MarkdownScanLimit.tabColumnWidth - (columns % MarkdownScanLimit.tabColumnWidth))
                if next > MarkdownScanLimit.maximumOpeningIndent { return nil }
                columns = next
                index += 1
            } else {
                break
            }
        }
        if columns > MarkdownScanLimit.maximumOpeningIndent { return nil }
        guard index < end, bytes[index] == ASCIIByte.leftBracket, !isEscapedByte(bytes, index) else {
            return nil
        }
        let opening = index
        index += 1
        let labelStart = index
        while index < end {
            if bytes[index] == ASCIIByte.backslash, index + 1 < end {
                index += 2
                continue
            }
            if bytes[index] == ASCIIByte.leftBracket || bytes[index] == ASCIIByte.lineFeed { return nil }
            if bytes[index] == ASCIIByte.rightBracket { break }
            index += 1
        }
        guard index < end, bytes[index] == ASCIIByte.rightBracket else { return nil }
        let labelEnd = index
        let closing = index
        guard labelEnd > labelStart, labelEnd - labelStart <= MarkdownScanLimit.maximumReferenceLabelLength else {
            return nil
        }
        index += 1
        guard index < end, bytes[index] == ASCIIByte.colon else { return nil }
        let colon = index
        index += 1
        index = skipHorizontalSpace(bytes, index, end)
        guard index < end else { return nil }

        var destination: Range<Int>
        var destinationOpening: Int?
        var destinationClosing: Int?
        if bytes[index] == ASCIIByte.lessThan {
            destinationOpening = index
            let destinationStart = index + 1
            var cursor = destinationStart
            while cursor < end, bytes[cursor] != ASCIIByte.greaterThan, bytes[cursor] != ASCIIByte.lineFeed {
                if bytes[cursor] == ASCIIByte.backslash, cursor + 1 < end {
                    cursor += 2
                    continue
                }
                if bytes[cursor] == ASCIIByte.lessThan { return nil }
                cursor += 1
            }
            guard cursor < end, bytes[cursor] == ASCIIByte.greaterThan, cursor > destinationStart else {
                return nil
            }
            destination = destinationStart..<cursor
            destinationClosing = cursor
            index = cursor + 1
        } else {
            let destinationStart = index
            var depth = 0
            while index < end {
                let byte = bytes[index]
                if byte == ASCIIByte.backslash, index + 1 < end {
                    index += 2
                    continue
                }
                if byte.isHorizontalSpace { break }
                if byte.isASCIIControl { return nil }
                if byte == ASCIIByte.leftParenthesis {
                    depth += 1
                } else if byte == ASCIIByte.rightParenthesis {
                    if depth == 0 { break }
                    depth -= 1
                }
                index += 1
            }
            guard index > destinationStart, depth == 0 else { return nil }
            destination = destinationStart..<index
        }

        index = skipHorizontalSpace(bytes, index, end)
        var title: Range<Int>?
        var titleOpening: Int?
        var titleClosing: Int?
        if index < end {
            let marker = bytes[index]
            let closingMarker: UInt8
            if marker == ASCIIByte.quotationMark || marker == ASCIIByte.apostrophe {
                closingMarker = marker
            } else if marker == ASCIIByte.leftParenthesis {
                closingMarker = ASCIIByte.rightParenthesis
            } else {
                return nil
            }
            titleOpening = index
            index += 1
            let titleStart = index
            while index < end, bytes[index] != closingMarker {
                if bytes[index] == ASCIIByte.backslash, index + 1 < end {
                    index += 2
                    continue
                }
                index += 1
            }
            guard index < end, bytes[index] == closingMarker else { return nil }
            title = titleStart..<index
            titleClosing = index
            index += 1
            index = skipHorizontalSpace(bytes, index, end)
            guard index == end else { return nil }
        }

        let label = String(decoding: bytes[labelStart..<labelEnd], as: UTF8.self)
        let normalized = normalizeReferenceLabel(label)
        guard !normalized.isEmpty, label.count <= MarkdownScanLimit.maximumReferenceLabelLength else {
            return nil
        }
        return ReferenceDefinitionParse(
            normalizedLabel: normalized,
            openingBracket: opening,
            label: labelStart..<labelEnd,
            closingBracket: closing,
            colon: colon,
            destination: destination,
            destinationOpening: destinationOpening,
            destinationClosing: destinationClosing,
            title: title,
            titleOpening: titleOpening,
            titleClosing: titleClosing
        )
    }
}

private func skipHorizontalSpace(_ bytes: [UInt8], _ start: Int, _ end: Int) -> Int {
    var index = start
    while index < end, bytes[index].isHorizontalSpace {
        index += 1
    }
    return index
}

private func isEscapedByte(_ bytes: [UInt8], _ index: Int) -> Bool {
    var slashCount = 0
    var cursor = index - 1
    while cursor >= 0, bytes[cursor] == ASCIIByte.backslash {
        slashCount += 1
        cursor -= 1
    }
    return slashCount % 2 == 1
}

// MARK: - Line predicates

private func content(_ line: TextLine, _ bytes: [UInt8]) -> ArraySlice<UInt8> {
    bytes[line.byteStart..<line.contentByteEnd]
}

private func isBlank(_ line: TextLine, bytes: [UInt8]) -> Bool {
    for byte in content(line, bytes) {
        if byte != ASCIIByte.space && byte != ASCIIByte.tab { return false }
    }
    return true
}

private func leadingWhitespace(_ slice: ArraySlice<UInt8>) -> (columns: Int, bytes: Int) {
    var columns = 0
    var count = 0
    for byte in slice {
        if byte == ASCIIByte.space {
            columns += 1
            count += 1
        } else if byte == ASCIIByte.tab {
            columns += MarkdownScanLimit.tabColumnWidth - (columns % MarkdownScanLimit.tabColumnWidth)
            count += 1
        } else {
            break
        }
    }
    return (columns, count)
}

private func isHashHeading(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > MarkdownScanLimit.maximumOpeningIndent { return false }
    var index = slice.startIndex + lead.bytes
    var hashes = 0
    while index < slice.endIndex && slice[index] == ASCIIByte.hash && hashes < MarkdownScanLimit.maximumHeadingLevel + 1 {
        hashes += 1
        index += 1
    }
    guard (1...6).contains(hashes) else { return false }
    if index == slice.endIndex { return true }
    return slice[index].isHorizontalSpace
}

private func openingFence(_ line: TextLine, bytes: [UInt8]) -> (marker: UInt8, length: Int)? {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > MarkdownScanLimit.maximumOpeningIndent { return nil }
    var index = slice.startIndex + lead.bytes
    guard index < slice.endIndex else { return nil }
    let marker = slice[index]
    guard marker == ASCIIByte.backtick || marker == ASCIIByte.tilde else { return nil }
    var length = 0
    while index < slice.endIndex && slice[index] == marker {
        length += 1
        index += 1
    }
    guard length >= 3 else { return nil }
    if marker == ASCIIByte.backtick {
        while index < slice.endIndex {
            if slice[index] == ASCIIByte.backtick { return nil }
            index += 1
        }
    }
    return (marker, length)
}

private func fenceCloser(_ line: TextLine, bytes: [UInt8], marker: UInt8, minimum: Int) -> Bool {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > MarkdownScanLimit.maximumOpeningIndent { return false }
    var index = slice.startIndex + lead.bytes
    var length = 0
    while index < slice.endIndex && slice[index] == marker {
        length += 1
        index += 1
    }
    guard length >= minimum else { return false }
    while index < slice.endIndex {
        let byte = slice[index]
        if byte != ASCIIByte.space && byte != ASCIIByte.tab { return false }
        index += 1
    }
    return true
}

private func isThematic(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > MarkdownScanLimit.maximumOpeningIndent { return false }
    var index = slice.startIndex + lead.bytes
    guard index < slice.endIndex else { return false }
    let marker = slice[index]
    guard marker == ASCIIByte.asterisk || marker == ASCIIByte.hyphen || marker == ASCIIByte.underscore else {
        return false
    }
    var count = 0
    while index < slice.endIndex {
        let byte = slice[index]
        if byte == marker {
            count += 1
        } else if byte != ASCIIByte.space && byte != ASCIIByte.tab {
            return false
        }
        index += 1
    }
    return count >= 3
}

private func underlineHeadingLevel(_ line: TextLine, bytes: [UInt8]) -> Int? {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > MarkdownScanLimit.maximumOpeningIndent { return nil }
    var index = slice.startIndex + lead.bytes
    guard index < slice.endIndex else { return nil }
    let marker = slice[index]
    guard marker == ASCIIByte.equalsSign || marker == ASCIIByte.hyphen else { return nil }
    while index < slice.endIndex && slice[index] == marker {
        index += 1
    }
    while index < slice.endIndex {
        let byte = slice[index]
        if byte != ASCIIByte.space && byte != ASCIIByte.tab { return nil }
        index += 1
    }
    return marker == ASCIIByte.equalsSign ? 1 : 2
}

private func isQuote(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > MarkdownScanLimit.maximumOpeningIndent { return false }
    let index = slice.startIndex + lead.bytes
    return index < slice.endIndex && slice[index] == ASCIIByte.greaterThan
}

private func isList(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > MarkdownScanLimit.maximumOpeningIndent { return false }
    var index = slice.startIndex + lead.bytes
    guard index < slice.endIndex else { return false }
    let byte = slice[index]
    if byte == ASCIIByte.hyphen || byte == ASCIIByte.plus || byte == ASCIIByte.asterisk {
        let next = index + 1
        if next >= slice.endIndex { return true }
        return slice[next].isHorizontalSpace
    }
    var digits = 0
    while index < slice.endIndex && slice[index].isASCIIDigit && digits < MarkdownScanLimit.maximumOrderedListMarkerDigits {
        digits += 1
        index += 1
    }
    guard digits > 0, index < slice.endIndex else { return false }
    let suffix = slice[index]
    guard suffix == ASCIIByte.period || suffix == ASCIIByte.rightParenthesis else { return false }
    let next = index + 1
    if next >= slice.endIndex { return true }
    return slice[next].isHorizontalSpace
}

private func isIndentedCode(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let lead = leadingWhitespace(content(line, bytes))
    return lead.columns >= 4 && !isBlank(line, bytes: bytes)
}

private func containsPipe(_ line: TextLine, bytes: [UInt8]) -> Bool {
    content(line, bytes).contains(ASCIIByte.verticalBar)
}

private func isTableDelimiter(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let slice = content(line, bytes)
    var index = slice.startIndex
    var sawCell = false
    var sawPipe = false
    func skipSpace() {
        while index < slice.endIndex && (slice[index].isHorizontalSpace) {
            index += 1
        }
    }
    skipSpace()
    if index < slice.endIndex && slice[index] == ASCIIByte.verticalBar {
        sawPipe = true
        index += 1
    }
    while index < slice.endIndex {
        skipSpace()
        if index < slice.endIndex && slice[index] == ASCIIByte.colon { index += 1 }
        var dashes = 0
        while index < slice.endIndex && slice[index] == ASCIIByte.hyphen {
            dashes += 1
            index += 1
        }
        if dashes == 0 { return false }
        if index < slice.endIndex && slice[index] == ASCIIByte.colon { index += 1 }
        skipSpace()
        sawCell = true
        if index < slice.endIndex && slice[index] == ASCIIByte.verticalBar {
            sawPipe = true
            index += 1
            continue
        }
        break
    }
    skipSpace()
    return sawPipe && sawCell && index == slice.endIndex
}

private func opensBlockAfterTable(_ line: TextLine, bytes: [UInt8]) -> Bool {
    isHashHeading(line, bytes: bytes) || openingFence(line, bytes: bytes) != nil || isQuote(line, bytes: bytes)
}

private enum HTMLBlockEnd: Equatable {
    case closingTag([UInt8])
    case comment
    case processingInstruction
    case declaration
    case characterData
    case blankLine
}

private let htmlBlockTags: Set<String> = [
    "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center",
    "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset",
    "figcaption", "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5",
    "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu",
    "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "search", "section",
    "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul",
]

private let htmlRawTags: Set<String> = ["script", "pre", "style", "textarea"]

private func htmlBlockOpening(_ line: TextLine, bytes: [UInt8], paragraphContinuation: Bool) -> HTMLBlockEnd? {
    let sliceEnd = line.contentByteEnd
    var index = line.byteStart
    var columns = 0
    while index < sliceEnd && columns <= MarkdownScanLimit.maximumOpeningIndent {
        if bytes[index] == ASCIIByte.space {
            columns += 1
            index += 1
        } else if bytes[index] == ASCIIByte.tab {
            let next = columns + (MarkdownScanLimit.tabColumnWidth - (columns % MarkdownScanLimit.tabColumnWidth))
            if next > MarkdownScanLimit.maximumOpeningIndent { return nil }
            columns = next
            index += 1
        } else {
            break
        }
    }
    if columns > MarkdownScanLimit.maximumOpeningIndent || index >= sliceEnd || bytes[index] != ASCIIByte.lessThan {
        return nil
    }
    if hasASCIIPrefix(bytes, at: index, end: sliceEnd, ascii: "<!--") { return .comment }
    if hasASCIIPrefix(bytes, at: index, end: sliceEnd, ascii: "<![CDATA[") { return .characterData }
    let afterBracket = index + 1
    if afterBracket < sliceEnd, bytes[afterBracket] == ASCIIByte.questionMark {
        return .processingInstruction
    }
    if afterBracket < sliceEnd, bytes[afterBracket] == ASCIIByte.exclamationMark {
        let letterIndex = afterBracket + 1
        if letterIndex < sliceEnd, bytes[letterIndex].isASCIILetter { return .declaration }
        return nil
    }

    var nameStart = afterBracket
    if nameStart < sliceEnd, bytes[nameStart] == ASCIIByte.slash { nameStart += 1 }
    guard nameStart < sliceEnd, bytes[nameStart].isASCIILetter else { return nil }
    var nameEnd = nameStart + 1
    while nameEnd < sliceEnd {
        let byte = bytes[nameEnd]
        if byte.isASCIILetter || byte.isASCIIDigit || byte == ASCIIByte.hyphen {
            nameEnd += 1
        } else {
            break
        }
    }
    let name = asciiLowercased(bytes, nameStart, nameEnd)
    guard tagBoundaryFollows(bytes, nameEnd, sliceEnd) else {
        if paragraphContinuation { return nil }
        return completeHTMLTag(bytes, tagStart: index, lineEnd: sliceEnd) ? .blankLine : nil
    }
    if htmlRawTags.contains(name) { return .closingTag(Array("</\(name)>".utf8)) }
    if htmlBlockTags.contains(name) { return .blankLine }
    if paragraphContinuation { return nil }
    return completeHTMLTag(bytes, tagStart: index, lineEnd: sliceEnd) ? .blankLine : nil
}

private func tagBoundaryFollows(_ bytes: [UInt8], _ index: Int, _ end: Int) -> Bool {
    if index >= end { return true }
    let byte = bytes[index]
    if byte.isHorizontalSpace || byte == ASCIIByte.greaterThan { return true }
    if byte == ASCIIByte.slash {
        return index + 1 == end || bytes[index + 1] == ASCIIByte.greaterThan || bytes[index + 1].isHorizontalSpace
    }
    return false
}

private func completeHTMLTag(_ bytes: [UInt8], tagStart: Int, lineEnd: Int) -> Bool {
    var index = tagStart + 1
    guard index < lineEnd else { return false }
    if bytes[index] == ASCIIByte.slash { index += 1 }
    guard index < lineEnd, bytes[index].isASCIILetter else { return false }
    index += 1
    while index < lineEnd {
        let byte = bytes[index]
        if byte.isASCIILetter || byte.isASCIIDigit || byte == ASCIIByte.hyphen {
            index += 1
        } else {
            break
        }
    }
    var quote: UInt8?
    while index < lineEnd {
        let byte = bytes[index]
        if let openQuote = quote {
            if byte == ASCIIByte.backslash, index + 1 < lineEnd {
                index += 2
                continue
            }
            if byte == openQuote { quote = nil }
            index += 1
            continue
        }
        if byte == ASCIIByte.quotationMark || byte == ASCIIByte.apostrophe {
            quote = byte
            index += 1
            continue
        }
        if byte == ASCIIByte.greaterThan {
            index += 1
            while index < lineEnd {
                if bytes[index] != ASCIIByte.space && bytes[index] != ASCIIByte.tab { return false }
                index += 1
            }
            return true
        }
        index += 1
    }
    return false
}

private func htmlEndIsSatisfied(_ end: HTMLBlockEnd, line: TextLine, bytes: [UInt8]) -> Bool {
    switch end {
    case .blankLine: return false
    case .comment: return lineContains(bytes, line, ascii: "-->")
    case .processingInstruction: return lineContains(bytes, line, ascii: "?>")
    case .declaration: return lineContains(bytes, line, ascii: ">")
    case .characterData: return lineContains(bytes, line, ascii: "]]>")
    case .closingTag(let needle): return lineContainsCaseInsensitive(bytes, line, needle)
    }
}

private func hasASCIIPrefix(_ bytes: [UInt8], at index: Int, end: Int, ascii: String) -> Bool {
    let prefix = Array(ascii.utf8)
    guard index + prefix.count <= end else { return false }
    return Array(bytes[index..<(index + prefix.count)]) == prefix
}

private func lineContains(_ bytes: [UInt8], _ line: TextLine, ascii: String) -> Bool {
    let needle = Array(ascii.utf8)
    let start = line.byteStart
    let end = line.contentByteEnd
    guard needle.count <= end - start else { return false }
    var index = start
    while index + needle.count <= end {
        if Array(bytes[index..<(index + needle.count)]) == needle { return true }
        index += 1
    }
    return false
}

private func lineContainsCaseInsensitive(_ bytes: [UInt8], _ line: TextLine, _ needle: [UInt8]) -> Bool {
    let start = line.byteStart
    let end = line.contentByteEnd
    guard needle.count <= end - start else { return false }
    var index = start
    while index + needle.count <= end {
        var matches = true
        for offset in needle.indices {
            if asciiLower(bytes[index + offset]) != needle[offset] {
                matches = false
                break
            }
        }
        if matches { return true }
        index += 1
    }
    return false
}

private func asciiLowercased(_ bytes: [UInt8], _ start: Int, _ end: Int) -> String {
    var characters: [UInt8] = []
    characters.reserveCapacity(end - start)
    for index in start..<end {
        characters.append(asciiLower(bytes[index]))
    }
    return String(decoding: characters, as: UTF8.self)
}

private func asciiLower(_ byte: UInt8) -> UInt8 {
    let uppercaseToLowercase = ASCIIByte.lowercaseA - ASCIIByte.uppercaseA
    if byte.isASCIILetter, byte <= ASCIIByte.uppercaseZ { return byte + uppercaseToLowercase }
    return byte
}

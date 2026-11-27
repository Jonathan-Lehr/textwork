/// Turns classified blocks into highlight spans.
///
/// Syntax characters and content are separate spans so later editing modes can
/// dim or hide the markers without parsing again.
enum BlockStyler {
    static func style(
        bytes: [UInt8],
        lines: [TextLine],
        startLine: Int,
        endLine: Int,
        kind: StructureKind,
        definedLabels: Set<String>
    ) -> (spans: [HighlightSpan], candidateLabels: [String]) {
        var spans: [HighlightSpan] = []
        var candidateLabels: [String] = []
        switch kind {
        case .hashHeading(let level):
            styleHashHeading(
                bytes: bytes,
                line: lines[startLine],
                level: level,
                definedLabels: definedLabels,
                candidateLabels: &candidateLabels,
                into: &spans
            )
        case .underlineHeading(let level):
            styleUnderlineHeading(
                bytes: bytes,
                lines: lines,
                startLine: startLine,
                endLine: endLine,
                level: level,
                definedLabels: definedLabels,
                candidateLabels: &candidateLabels,
                into: &spans
            )
        case .fence: styleFence(bytes: bytes, lines: lines, startLine: startLine, endLine: endLine, into:
            &spans)
        case .thematic:
            let line = lines[startLine]
            append(line.byteStart..<line.contentByteEnd, role: .thematicBreak, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
        case .quote:
            styleQuote(
                bytes: bytes,
                lines: lines,
                startLine: startLine,
                endLine: endLine,
                definedLabels: definedLabels,
                candidateLabels: &candidateLabels,
                into: &spans
            )
        case .list:
            styleList(
                bytes: bytes,
                line: lines[startLine],
                definedLabels: definedLabels,
                candidateLabels: &candidateLabels,
                into: &spans
            )
        case .indentedCode:
            styleIndentedCode(bytes: bytes, lines: lines, startLine: startLine, endLine: endLine, into: &spans)
        case .paragraph:
            let range = contentByteRange(lines: lines, startLine: startLine, endLine: endLine)
            spans.append(contentsOf: InlineStyler.spans(
                bytes: bytes,
                range: range,
                lines: lines,
                definedLabels: definedLabels,
                candidateLabels: &candidateLabels
            ))
        case .table:
            styleTable(
                bytes: bytes,
                lines: lines,
                startLine: startLine,
                endLine: endLine,
                definedLabels: definedLabels,
                candidateLabels: &candidateLabels,
                into: &spans
            )
        case .referenceDefinition: styleReferenceDefinition(bytes: bytes, line: lines[startLine], into:
            &spans)
        case .htmlBlock:
            let range = contentByteRange(lines: lines, startLine: startLine, endLine: endLine)
            spans.append(contentsOf: InlineStyler.htmlSpans(bytes: bytes, range: range, lines: lines, allowMultilineMarkup: true))
        }
        return (spans, Array(Set(candidateLabels)).sorted())
    }

    static func contentByteRange(lines: [TextLine], startLine: Int, endLine: Int) -> Range<Int> {
        guard startLine < endLine else { return 0..<0 }
        return lines[startLine].byteStart..<lines[endLine - 1].contentByteEnd
    }
}

private enum InlineStyler {
    static func spans(
        bytes: [UInt8],
        range: Range<Int>,
        lines: [TextLine],
        definedLabels: Set<String>,
        candidateLabels: inout [String]
    ) -> [HighlightSpan] {
        guard range.lowerBound < range.upperBound else { return [] }
        var raw: [RawSpan] = []
        var mask = ByteMask()
        scanCodeSpans(bytes: bytes, range: range, mask: &mask, into: &raw)
        scanLinksAndImages(
            bytes: bytes,
            range: range,
            mask: &mask,
            definedLabels: definedLabels,
            candidateLabels: &candidateLabels,
            into: &raw
        )
        scanAutolinks(bytes: bytes, range: range, mask: &mask, into: &raw)
        scanInlineHTML(bytes: bytes, range: range, mask: &mask, allowMultilineMarkup: false, into: &raw)
        scanEmphasis(bytes: bytes, range: range, mask: mask, into: &raw)
        return raw.compactMap { $0.span(bytes: bytes, lines: lines) }
    }

    static func htmlSpans(bytes: [UInt8], range: Range<Int>, lines: [TextLine], allowMultilineMarkup: Bool) -> [HighlightSpan] {
        guard range.lowerBound < range.upperBound else { return [] }
        var raw: [RawSpan] = []
        var mask = ByteMask()
        scanInlineHTML(
            bytes: bytes,
            range: range,
            mask: &mask,
            allowMultilineMarkup: allowMultilineMarkup,
            into: &raw
        )
        return raw.compactMap { $0.span(bytes: bytes, lines: lines) }
    }
}

private struct RawSpan {
    var byteRange: Range<Int>
    var role: HighlightRole
    var isSyntax: Bool

    func span(bytes: [UInt8], lines: [TextLine]) -> HighlightSpan? {
        guard byteRange.upperBound > byteRange.lowerBound else { return nil }
        let start = utf16Offset(of: byteRange.lowerBound, bytes: bytes, lines: lines)
        let end = utf16Offset(of: byteRange.upperBound, bytes: bytes, lines: lines)
        guard end > start else { return nil }
        return HighlightSpan(startUTF16: start, endUTF16: end, role: role, isSyntax: isSyntax)
    }
}

private struct ByteMask {
    private var ranges: [Range<Int>] = []

    mutating func cover(_ range: Range<Int>) {
        guard range.upperBound > range.lowerBound else { return }
        ranges.append(range)
    }

    func covers(_ index: Int) -> Bool {
        ranges.contains { $0.contains(index) }
    }

    func endOfCover(containing index: Int) -> Int? {
        ranges.first { $0.contains(index) }?.upperBound
    }
}

private enum FlankingClass {
    case whitespace
    case punctuation
    case word
}

private struct DelimiterRun {
    var marker: UInt8
    var startByte: Int
    var remaining: Int
    var canOpen: Bool
    var canClose: Bool
}

private func styleHashHeading(
    bytes: [UInt8],
    line: TextLine,
    level: Int,
    definedLabels: Set<String>,
    candidateLabels: inout [String],
    into spans: inout [HighlightSpan]
) {
    let role = HighlightRole.heading(level: level)
    let sliceStart = line.byteStart
    let sliceEnd = line.contentByteEnd
    let lead = leadingByteCount(bytes, from: sliceStart, to: sliceEnd, columnLimit: MarkdownScanLimit.maximumOpeningIndent)
    var index = sliceStart + lead
    let hashStart = index
    while index < sliceEnd && bytes[index] == ASCIIByte.hash {
        index += 1
    }
    append(hashStart..<index, role: role, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    if index < sliceEnd && (bytes[index].isHorizontalSpace) {
        append(index..<(index + 1), role: role, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
        index += 1
    }
    var contentEnd = sliceEnd
    var trim = sliceEnd
    while trim > index && (bytes[trim - 1].isHorizontalSpace) {
        trim -= 1
    }
    var hashEnd = trim
    while hashEnd > index && bytes[hashEnd - 1] == ASCIIByte.hash {
        hashEnd -= 1
    }
    if hashEnd < trim, hashEnd > index, bytes[hashEnd - 1].isHorizontalSpace {
        contentEnd = hashEnd - 1
        append(contentEnd..<sliceEnd, role: role, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    }
    if index < contentEnd {
        append(index..<contentEnd, role: role, isSyntax: false, bytes: bytes, lines: [], lineHint: line, into: &spans)
        let inline = InlineStyler.spans(
            bytes: bytes,
            range: index..<contentEnd,
            lines: [line],
            definedLabels: definedLabels,
            candidateLabels: &candidateLabels
        )
        spans.append(contentsOf: inline)
    }
}

private func styleUnderlineHeading(
    bytes: [UInt8],
    lines: [TextLine],
    startLine: Int,
    endLine: Int,
    level: Int,
    definedLabels: Set<String>,
    candidateLabels: inout [String],
    into spans: inout [HighlightSpan]
) {
    let role = HighlightRole.heading(level: level)
    let underline = endLine - 1
    if underline > startLine {
        let content = BlockStyler.contentByteRange(lines: lines, startLine: startLine, endLine: underline)
        append(content, role: role, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
        spans.append(contentsOf: InlineStyler.spans(
            bytes: bytes,
            range: content,
            lines: lines,
            definedLabels: definedLabels,
            candidateLabels: &candidateLabels
        ))
    }
    let marker = lines[underline]
    append(marker.byteStart..<marker.contentByteEnd, role: role, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
}

private func styleFence(
    bytes: [UInt8],
    lines: [TextLine],
    startLine: Int,
    endLine: Int,
    into spans: inout [HighlightSpan]
) {
    let language = startLine < endLine
        ? FencedCodeTokenizer.language(
            onOpeningFence: bytes,
            range: lines[startLine].byteStart..<lines[startLine].contentByteEnd
        )
        : nil
    var scanState = FencedCodeScanState()
    for lineIndex in startLine..<endLine {
        let line = lines[lineIndex]
        let range = line.byteStart..<line.contentByteEnd
        switch line.kind {
        case .fenceOpen, .fenceClose:
            append(range, role: .codeBlock, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
        default:
            append(range, role: .codeBlock, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
            if let language {
                let tokens = FencedCodeTokenizer.tokens(
                    bytes: bytes,
                    range: range,
                    language: language,
                    state: &scanState
                )
                for token in tokens {
                    append(token.byteRange, role: token.role, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
                }
            }
        }
    }
}

private func styleIndentedCode(
    bytes: [UInt8],
    lines: [TextLine],
    startLine: Int,
    endLine: Int,
    into spans: inout [HighlightSpan]
) {
    for lineIndex in startLine..<endLine {
        let line = lines[lineIndex]
        var index = line.byteStart
        var columns = 0
        while index < line.contentByteEnd && columns < MarkdownScanLimit.codeBlockIndent {
            if bytes[index] == ASCIIByte.space {
                columns += 1
                index += 1
            } else if bytes[index] == ASCIIByte.tab {
                columns += MarkdownScanLimit.tabColumnWidth - (columns % MarkdownScanLimit.tabColumnWidth)
                index += 1
            } else {
                break
            }
        }
        append(index..<line.contentByteEnd, role: .codeBlock, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
    }
}

private func styleQuote(
    bytes: [UInt8],
    lines: [TextLine],
    startLine: Int,
    endLine: Int,
    definedLabels: Set<String>,
    candidateLabels: inout [String],
    into spans: inout [HighlightSpan]
) {
    for lineIndex in startLine..<endLine {
        let line = lines[lineIndex]
        var index = line.byteStart
        let limit = line.contentByteEnd
        let lead = leadingByteCount(bytes, from: index, to: limit, columnLimit: MarkdownScanLimit.maximumOpeningIndent)
        index += lead
        while index < limit && bytes[index] == ASCIIByte.greaterThan {
            let markerStart = index
            index += 1
            if index < limit && bytes[index] == ASCIIByte.space { index += 1 }
            append(markerStart..<index, role: .blockQuote, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
        }
        if index < limit {
            let content = index..<limit
            if let heading = headingPrefix(bytes: bytes, range: content) {
                append(heading.marker, role: heading.role, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
                if heading.content.lowerBound < heading.content.upperBound {
                    append(heading.content, role: heading.role, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
                    spans.append(contentsOf: InlineStyler.spans(
                        bytes: bytes,
                        range: heading.content,
                        lines: lines,
                        definedLabels: definedLabels,
                        candidateLabels: &candidateLabels
                    ))
                }
            } else {
                spans.append(contentsOf: InlineStyler.spans(
                    bytes: bytes,
                    range: content,
                    lines: lines,
                    definedLabels: definedLabels,
                    candidateLabels: &candidateLabels
                ))
            }
        }
    }
}

private func styleList(
    bytes: [UInt8],
    line: TextLine,
    definedLabels: Set<String>,
    candidateLabels: inout [String],
    into spans: inout [HighlightSpan]
) {
    let limit = line.contentByteEnd
    var index = line.byteStart
    index += leadingByteCount(bytes, from: index, to: limit, columnLimit: MarkdownScanLimit.maximumOpeningIndent)
    let markerStart = index
    if index < limit && (bytes[index] == ASCIIByte.hyphen || bytes[index] == ASCIIByte.plus || bytes[index] == ASCIIByte.asterisk) {
        index += 1
    } else {
        while index < limit && bytes[index].isASCIIDigit {
            index += 1
        }
        if index < limit && (bytes[index] == ASCIIByte.period || bytes[index] == ASCIIByte.rightParenthesis) {
            index += 1
        }
    }
    while index < limit && (bytes[index].isHorizontalSpace) {
        index += 1
        break
    }
    if index + 2 < limit, bytes[index] == ASCIIByte.leftBracket, bytes[index + 2] == ASCIIByte.rightBracket {
        let checkbox = bytes[index + 1]
        if checkbox == ASCIIByte.space || checkbox == ASCIIByte.lowercaseX || checkbox == ASCIIByte.uppercaseX {
            index += 3
            if index < limit && (bytes[index].isHorizontalSpace) { index += 1 }
        }
    }
    append(markerStart..<index, role: .listMarker, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    if index < limit {
        spans.append(contentsOf: InlineStyler.spans(
            bytes: bytes,
            range: index..<limit,
            lines: [line],
            definedLabels: definedLabels,
            candidateLabels: &candidateLabels
        ))
    }
}

private func styleTable(
    bytes: [UInt8],
    lines: [TextLine],
    startLine: Int,
    endLine: Int,
    definedLabels: Set<String>,
    candidateLabels: inout [String],
    into spans: inout [HighlightSpan]
) {
    for lineIndex in startLine..<endLine {
        let line = lines[lineIndex]
        if line.kind == .tableDelimiter {
            append(line.byteStart..<line.contentByteEnd, role: .table, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
            continue
        }
        let cells = tableCells(bytes: bytes, line: line)
        for cell in cells {
            switch cell {
            case .pipe(let range): append(range, role: .table, isSyntax: true, bytes: bytes, lines: lines, into:
                &spans)
            case .text(let range):
                append(range, role: .table, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
                spans.append(contentsOf: InlineStyler.spans(
                    bytes: bytes,
                    range: range,
                    lines: lines,
                    definedLabels: definedLabels,
                    candidateLabels: &candidateLabels
                ))
            }
        }
    }
}

private enum TableCell {
    case pipe(Range<Int>)
    case text(Range<Int>)
}

private func tableCells(bytes: [UInt8], line: TextLine) -> [TableCell] {
    var cells: [TableCell] = []
    var index = line.byteStart
    let limit = line.contentByteEnd
    var textStart = index
    while index < limit {
        if bytes[index] == ASCIIByte.backslash, index + 1 < limit {
            index += 2
            continue
        }
        if bytes[index] == ASCIIByte.verticalBar {
            let trimmed = trimSpaces(bytes, textStart..<index)
            if !trimmed.isEmpty { cells.append(.text(trimmed)) }
            cells.append(.pipe(index..<(index + 1)))
            index += 1
            textStart = index
            continue
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
    let trimmed = trimSpaces(bytes, textStart..<limit)
    if !trimmed.isEmpty { cells.append(.text(trimmed)) }
    return cells
}

private func scanCodeSpans(bytes: [UInt8], range: Range<Int>, mask: inout ByteMask, into raw: inout [RawSpan]) {
    var index = range.lowerBound
    while index < range.upperBound {
        if bytes[index] != ASCIIByte.backtick || isEscaped(bytes, index) {
            index += DocumentBuffer.scalarWidth(bytes, index).0
            continue
        }
        let openerLength = runLength(bytes, index, marker: ASCIIByte.backtick, limit: range.upperBound)
        var cursor = index + openerLength
        var closer: Int?
        while cursor < range.upperBound {
            if bytes[cursor] == ASCIIByte.backtick && !isEscaped(bytes, cursor) {
                let length = runLength(bytes, cursor, marker: ASCIIByte.backtick, limit: range.upperBound)
                if length == openerLength {
                    closer = cursor
                    break
                }
                cursor += length
            } else {
                cursor += DocumentBuffer.scalarWidth(bytes, cursor).0
            }
        }
        guard let closer else {
            index += openerLength
            continue
        }
        raw.append(RawSpan(byteRange: index..<(index + openerLength), role: .codeSpan, isSyntax: true))
        let content = (index + openerLength)..<closer
        if !content.isEmpty { raw.append(RawSpan(byteRange: content, role: .codeSpan, isSyntax: false)) }
        raw.append(RawSpan(byteRange: closer..<(closer + openerLength), role: .codeSpan, isSyntax: true))
        mask.cover(index..<(closer + openerLength))
        index = closer + openerLength
    }
}

private func scanLinksAndImages(
    bytes: [UInt8],
    range: Range<Int>,
    mask: inout ByteMask,
    definedLabels: Set<String>,
    candidateLabels: inout [String],
    into raw: inout [RawSpan]
) {
    var index = range.lowerBound
    while index < range.upperBound {
        if let end = mask.endOfCover(containing: index) {
            index = end
            continue
        }
        let isImage = bytes[index] == ASCIIByte.exclamationMark && index + 1 < range.upperBound && bytes[index + 1] == ASCIIByte.leftBracket && !isEscaped(bytes, index)
        let isLink = bytes[index] == ASCIIByte.leftBracket && !isEscaped(bytes, index)
        guard isImage || isLink else {
            index += DocumentBuffer.scalarWidth(bytes, index).0
            continue
        }
        let role: HighlightRole = isImage ? .image : .link
        let bracket = isImage ? index + 1 : index
        guard let labelEnd = closingBracket(bytes: bytes, from: bracket + 1, limit: range.upperBound, mask: mask) else {
            index += 1
            continue
        }
        let afterLabel = labelEnd + 1
        if afterLabel < range.upperBound, bytes[afterLabel] == ASCIIByte.leftParenthesis {
            guard let destinationEnd = closingParenthesis(bytes: bytes, from: afterLabel + 1, limit: range.upperBound) else {
                index += 1
                continue
            }
            appendLinkLabel(
                bytes: bytes,
                role: role,
                markerStart: index,
                isImage: isImage,
                bracket: bracket,
                labelEnd: labelEnd,
                syntaxEnd: destinationEnd,
                mask: mask,
                into: &raw
            )
            mask.cover(index..<destinationEnd)
            index = destinationEnd
            continue
        }
        if let referenceEnd = referenceLinkEnd(
            bytes: bytes,
            range: range,
            bracket: bracket,
            labelEnd: labelEnd,
            mask: mask,
            definedLabels: definedLabels,
            candidateLabels: &candidateLabels
        ) {
            appendLinkLabel(
                bytes: bytes,
                role: role,
                markerStart: index,
                isImage: isImage,
                bracket: bracket,
                labelEnd: labelEnd,
                syntaxEnd: referenceEnd,
                mask: mask,
                into: &raw
            )
            mask.cover(index..<referenceEnd)
            index = referenceEnd
            continue
        }
        index += 1
    }
}

/// Returns the byte just past a defined reference link, and records every label the match depends on.
private func referenceLinkEnd(
    bytes: [UInt8],
    range: Range<Int>,
    bracket: Int,
    labelEnd: Int,
    mask: ByteMask,
    definedLabels: Set<String>,
    candidateLabels: inout [String]
) -> Int? {
    let linkText = normalizedLabel(bytes: bytes, range: (bracket + 1)..<labelEnd)
    let afterLabel = labelEnd + 1
    if afterLabel < range.upperBound, bytes[afterLabel] == ASCIIByte.leftBracket {
        let secondStart = afterLabel + 1
        if secondStart < range.upperBound, bytes[secondStart] == ASCIIByte.rightBracket {
            guard !linkText.isEmpty else { return nil }
            candidateLabels.append(linkText)
            return definedLabels.contains(linkText) ? secondStart + 1 : nil
        }
        guard let secondEnd = closingBracket(bytes: bytes, from: secondStart, limit: range.upperBound, mask: mask) else {
            guard !linkText.isEmpty else { return nil }
            candidateLabels.append(linkText)
            return definedLabels.contains(linkText) ? labelEnd + 1 : nil
        }
        let reference = normalizedLabel(bytes: bytes, range: secondStart..<secondEnd)
        if !reference.isEmpty { candidateLabels.append(reference) }
        if !linkText.isEmpty { candidateLabels.append(linkText) }
        if !reference.isEmpty, definedLabels.contains(reference) { return secondEnd + 1 }
        if !linkText.isEmpty, definedLabels.contains(linkText) { return labelEnd + 1 }
        return nil
    }
    guard !linkText.isEmpty else { return nil }
    candidateLabels.append(linkText)
    return definedLabels.contains(linkText) ? labelEnd + 1 : nil
}

private func appendLinkLabel(
    bytes: [UInt8],
    role: HighlightRole,
    markerStart: Int,
    isImage: Bool,
    bracket: Int,
    labelEnd: Int,
    syntaxEnd: Int,
    mask: ByteMask,
    into raw: inout [RawSpan]
) {
    if isImage { raw.append(RawSpan(byteRange: markerStart..<(markerStart + 1), role: role, isSyntax: true)) }
    raw.append(RawSpan(byteRange: bracket..<(bracket + 1), role: role, isSyntax: true))
    let label = (bracket + 1)..<labelEnd
    if !label.isEmpty {
        raw.append(RawSpan(byteRange: label, role: role, isSyntax: false))
        raw.append(contentsOf: emphasisSpans(bytes: bytes, range: label, mask: mask))
    }
    if syntaxEnd > labelEnd {
        raw.append(RawSpan(byteRange: labelEnd..<syntaxEnd, role: role, isSyntax: true))
    }
}

private func normalizedLabel(bytes: [UInt8], range: Range<Int>) -> String {
    guard range.upperBound > range.lowerBound else { return "" }
    return normalizeReferenceLabel(String(decoding: bytes[range], as: UTF8.self))
}

private func scanAutolinks(bytes: [UInt8], range: Range<Int>, mask: inout ByteMask, into raw: inout [RawSpan]) {
    var index = range.lowerBound
    while index < range.upperBound {
        if let end = mask.endOfCover(containing: index) {
            index = end
            continue
        }
        if bytes[index] == ASCIIByte.lessThan && !isEscaped(bytes, index) {
            if let end = autolinkEnd(bytes: bytes, open: index, limit: range.upperBound) {
                raw.append(RawSpan(byteRange: index..<(index + 1), role: .link, isSyntax: true))
                raw.append(RawSpan(byteRange: (index + 1)..<end, role: .link, isSyntax: false))
                raw.append(RawSpan(byteRange: end..<(end + 1), role: .link, isSyntax: true))
                mask.cover(index..<(end + 1))
                index = end + 1
                continue
            }
        }
        if startsWebAddress(bytes, index, limit: range.upperBound), !isEscaped(bytes, index) {
            let end = webAddressEnd(bytes, index, limit: range.upperBound)
            if end > index + 8 {
                raw.append(RawSpan(byteRange: index..<end, role: .link, isSyntax: false))
                mask.cover(index..<end)
                index = end
                continue
            }
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
}

private func scanInlineHTML(
    bytes: [UInt8],
    range: Range<Int>,
    mask: inout ByteMask,
    allowMultilineMarkup: Bool,
    into raw: inout [RawSpan]
) {
    var index = range.lowerBound
    while index < range.upperBound {
        if let end = mask.endOfCover(containing: index) {
            index = end
            continue
        }
        if bytes[index] == ASCIIByte.lessThan, !isEscaped(bytes, index),
           let markup = htmlMarkup(bytes: bytes, open: index, limit: range.upperBound, allowMultilineMarkup: allowMultilineMarkup) {
            raw.append(contentsOf: markup.spans)
            mask.cover(index..<markup.end)
            index = markup.end
            continue
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
}

private struct HTMLMarkup {
    var spans: [RawSpan]
    var end: Int
}

private func htmlMarkup(bytes: [UInt8], open: Int, limit: Int, allowMultilineMarkup: Bool) -> HTMLMarkup? {
    guard open + 1 < limit else { return nil }
    if hasBytes(bytes, at: open, limit: limit, ascii: "<!--") {
        guard let end = seek(bytes, from: open + 4, limit: limit, ascii: "-->", allowNewline: allowMultilineMarkup) else {
            return nil
        }
        return markup(open: open, delimiter: 4, body: (open + 4)..<end, closer: 3)
    }
    if hasBytes(bytes, at: open, limit: limit, ascii: "<![CDATA[") {
        guard let end = seek(bytes, from: open + 9, limit: limit, ascii: "]]>", allowNewline: allowMultilineMarkup) else {
            return nil
        }
        return markup(open: open, delimiter: 9, body: (open + 9)..<end, closer: 3)
    }
    if bytes[open + 1] == ASCIIByte.questionMark {
        guard let end = seek(bytes, from: open + 2, limit: limit, ascii: "?>", allowNewline: allowMultilineMarkup) else {
            return nil
        }
        return markup(open: open, delimiter: 2, body: (open + 2)..<end, closer: 2)
    }
    if bytes[open + 1] == ASCIIByte.exclamationMark {
        let letter = open + 2
        guard letter < limit, bytes[letter].isASCIILetter else { return nil }
        guard let end = seekByte(bytes, from: letter, limit: limit, byte: ASCIIByte.greaterThan, allowNewline: allowMultilineMarkup) else {
            return nil
        }
        return markup(open: open, delimiter: 2, body: (open + 2)..<end, closer: 1)
    }
    return htmlTag(bytes: bytes, open: open, limit: limit)
}

private func htmlTag(bytes: [UInt8], open: Int, limit: Int) -> HTMLMarkup? {
    var index = open + 1
    let closingTag = index < limit && bytes[index] == ASCIIByte.slash
    if closingTag { index += 1 }
    let nameStart = index
    guard index < limit, bytes[index].isASCIILetter else { return nil }
    index += 1
    while index < limit {
        let byte = bytes[index]
        if byte == ASCIIByte.lineFeed || byte == ASCIIByte.carriageReturn { return nil }
        if byte.isASCIILetter || byte.isASCIIDigit || byte == ASCIIByte.hyphen {
            index += 1
            continue
        }
        break
    }
    guard index > nameStart else { return nil }
    let nameEnd = index
    var quote: UInt8?
    while index < limit {
        let byte = bytes[index]
        if byte == ASCIIByte.lineFeed || byte == ASCIIByte.carriageReturn { return nil }
        if let openQuote = quote {
            if byte == ASCIIByte.backslash, index + 1 < limit, bytes[index + 1] != ASCIIByte.lineFeed, bytes[index + 1] != ASCIIByte.carriageReturn {
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
            let name = nameStart..<nameEnd
            var spans: [RawSpan] = []
            let openerEnd = closingTag ? open + 2 : open + 1
            spans.append(RawSpan(byteRange: open..<openerEnd, role: .html, isSyntax: true))
            if !name.isEmpty { spans.append(RawSpan(byteRange: name, role: .html, isSyntax: false)) }
            var closerStart = index
            if closerStart > nameEnd, bytes[closerStart - 1] == ASCIIByte.slash { closerStart -= 1 }
            if nameEnd < closerStart {
                spans.append(RawSpan(byteRange: nameEnd..<closerStart, role: .html, isSyntax: false))
            }
            spans.append(RawSpan(byteRange: closerStart..<(index + 1), role: .html, isSyntax: true))
            return HTMLMarkup(spans: spans, end: index + 1)
        }
        index += 1
    }
    return nil
}

private func markup(open: Int, delimiter: Int, body: Range<Int>, closer: Int) -> HTMLMarkup {
    var spans = [RawSpan(byteRange: open..<(open + delimiter), role: .html, isSyntax: true)]
    if !body.isEmpty { spans.append(RawSpan(byteRange: body, role: .html, isSyntax: false)) }
    let closerStart = body.upperBound
    spans.append(RawSpan(byteRange: closerStart..<(closerStart + closer), role: .html, isSyntax: true))
    return HTMLMarkup(spans: spans, end: closerStart + closer)
}

private func seek(_ bytes: [UInt8], from start: Int, limit: Int, ascii: String, allowNewline: Bool) -> Int? {
    let needle = Array(ascii.utf8)
    guard !needle.isEmpty else { return nil }
    var index = start
    while index + needle.count <= limit {
        if !allowNewline, bytes[index] == ASCIIByte.lineFeed || bytes[index] == ASCIIByte.carriageReturn {
            return nil
        }
        if Array(bytes[index..<(index + needle.count)]) == needle { return index }
        index += 1
    }
    return nil
}

private func seekByte(_ bytes: [UInt8], from start: Int, limit: Int, byte: UInt8, allowNewline: Bool) -> Int? {
    var index = start
    while index < limit {
        if !allowNewline, bytes[index] == ASCIIByte.lineFeed || bytes[index] == ASCIIByte.carriageReturn {
            return nil
        }
        if bytes[index] == byte { return index }
        index += 1
    }
    return nil
}

private func hasBytes(_ bytes: [UInt8], at index: Int, limit: Int, ascii: String) -> Bool {
    let prefix = Array(ascii.utf8)
    guard index + prefix.count <= limit else { return false }
    return Array(bytes[index..<(index + prefix.count)]) == prefix
}

private func styleReferenceDefinition(bytes: [UInt8], line: TextLine, into spans: inout [HighlightSpan]) {
    guard let parsed = ReferenceDefinitionParser.parseLine(bytes: bytes, line: line) else { return }
    append(parsed.openingBracket..<(parsed.openingBracket + 1), role: .link, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    append(parsed.label, role: .link, isSyntax: false, bytes: bytes, lines: [], lineHint: line, into: &spans)
    append(parsed.closingBracket..<(parsed.closingBracket + 1), role: .link, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    append(parsed.colon..<(parsed.colon + 1), role: .link, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    if let opening = parsed.destinationOpening {
        append(opening..<(opening + 1), role: .link, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    }
    append(parsed.destination, role: .link, isSyntax: false, bytes: bytes, lines: [], lineHint: line, into: &spans)
    if let closing = parsed.destinationClosing {
        append(closing..<(closing + 1), role: .link, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    }
    if let opening = parsed.titleOpening {
        append(opening..<(opening + 1), role: .link, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    }
    if let title = parsed.title, !title.isEmpty {
        append(title, role: .link, isSyntax: false, bytes: bytes, lines: [], lineHint: line, into: &spans)
    }
    if let closing = parsed.titleClosing {
        append(closing..<(closing + 1), role: .link, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    }
}

private func scanEmphasis(bytes: [UInt8], range: Range<Int>, mask: ByteMask, into raw: inout [RawSpan]) {
    raw.append(contentsOf: emphasisSpans(bytes: bytes, range: range, mask: mask))
}

private func emphasisSpans(bytes: [UInt8], range: Range<Int>, mask: ByteMask) -> [RawSpan] {
    var delimiters: [DelimiterRun] = []
    var index = range.lowerBound
    while index < range.upperBound {
        if let end = mask.endOfCover(containing: index) {
            index = end
            continue
        }
        let marker = bytes[index]
        if (marker == ASCIIByte.asterisk || marker == ASCIIByte.underscore), !isEscaped(bytes, index) {
            let length = runLength(bytes, index, marker: marker, limit: range.upperBound)
            let before = flankingClass(beforeByte: index, bytes: bytes, range: range, mask: mask)
            let after = flankingClass(afterByte: index + length, bytes: bytes, range: range, mask: mask)
            let (canOpen, canClose) = flanking(marker: marker, before: before, after: after)
            if canOpen || canClose {
                delimiters.append(
                    DelimiterRun(
                        marker: marker,
                        startByte: index,
                        remaining: length,
                        canOpen: canOpen,
                        canClose: canClose
                    )
                )
            }
            index += length
            continue
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }

    var spans: [RawSpan] = []
    var closerIndex = 0
    while closerIndex < delimiters.count {
        if !delimiters[closerIndex].canClose || delimiters[closerIndex].remaining == 0 {
            closerIndex += 1
            continue
        }
        var openerIndex = closerIndex - 1
        var matched = false
        while openerIndex >= 0 {
            let opener = delimiters[openerIndex]
            let closer = delimiters[closerIndex]
            if opener.marker == closer.marker, opener.canOpen, opener.remaining > 0, emphasisMatchAllowed(opener, closer) {
                let used = (opener.remaining >= 2 && closer.remaining >= 2) ? 2 : 1
                let role: HighlightRole = used == 2 ? .strong : .emphasis
                let openerByte = opener.startByte + (opener.remaining - used)
                let closerByte = closer.startByte
                spans.append(RawSpan(byteRange: openerByte..<(openerByte + used), role: role, isSyntax: true))
                let content = (openerByte + used)..<closerByte
                if !content.isEmpty { spans.append(RawSpan(byteRange: content, role: role, isSyntax: false)) }
                spans.append(RawSpan(byteRange: closerByte..<(closerByte + used), role: role, isSyntax: true))
                delimiters[openerIndex].remaining -= used
                delimiters[closerIndex].startByte += used
                delimiters[closerIndex].remaining -= used
                matched = true
                break
            }
            openerIndex -= 1
        }
        if !matched || delimiters[closerIndex].remaining == 0 { closerIndex += 1 }
    }
    return spans
}

private func emphasisMatchAllowed(_ opener: DelimiterRun, _ closer: DelimiterRun) -> Bool {
    let openerAmbiguous = opener.canOpen && opener.canClose
    let closerAmbiguous = closer.canOpen && closer.canClose
    if openerAmbiguous || closerAmbiguous {
        let sum = opener.remaining + closer.remaining
        if sum.isMultiple(of: 3), !opener.remaining.isMultiple(of: 3) || !closer.remaining.isMultiple(of: 3) {
            return false
        }
    }
    return true
}

private func flanking(marker: UInt8, before: FlankingClass, after: FlankingClass) -> (Bool, Bool) {
    let leftFlanking = after != .whitespace && !(after == .punctuation && before == .word)
    let rightFlanking = before != .whitespace && !(before == .punctuation && after == .word)
    if marker == ASCIIByte.underscore {
        let canOpen = leftFlanking && (!rightFlanking || before == .punctuation)
        let canClose = rightFlanking && (!leftFlanking || after == .punctuation)
        return (canOpen, canClose)
    }
    return (leftFlanking, rightFlanking)
}

private func flankingClass(beforeByte index: Int, bytes: [UInt8], range: Range<Int>, mask: ByteMask) -> FlankingClass {
    let previous = index - 1
    guard previous >= range.lowerBound else { return .whitespace }
    if mask.covers(previous) { return .punctuation }
    return flankingClass(of: bytes[previous])
}

private func flankingClass(afterByte index: Int, bytes: [UInt8], range: Range<Int>, mask: ByteMask) -> FlankingClass {
    guard index < range.upperBound else { return .whitespace }
    if mask.covers(index) { return .punctuation }
    return flankingClass(of: bytes[index])
}

private func flankingClass(of byte: UInt8) -> FlankingClass {
    switch byte {
    case ASCIIByte.space, ASCIIByte.tab, ASCIIByte.lineFeed, ASCIIByte.carriageReturn, ASCIIByte.verticalTab, ASCIIByte.formFeed:
        return .whitespace
    case ASCIIByte.exclamationMark...ASCIIByte.slash,
        ASCIIByte.colon...ASCIIByte.atSign,
        ASCIIByte.leftBracket...ASCIIByte.backtick,
        ASCIIByte.leftBrace...ASCIIByte.tilde:
        return .punctuation
    default: return .word
    }
}

private func closingBracket(bytes: [UInt8], from start: Int, limit: Int, mask: ByteMask) -> Int? {
    var index = start
    while index < limit {
        if let end = mask.endOfCover(containing: index) {
            index = end
            continue
        }
        if bytes[index] == ASCIIByte.rightBracket && !isEscaped(bytes, index) { return index }
        if bytes[index] == ASCIIByte.lineFeed || bytes[index] == ASCIIByte.leftBracket { return nil }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
    return nil
}

private func closingParenthesis(bytes: [UInt8], from start: Int, limit: Int) -> Int? {
    var index = start
    var depth = 1
    while index < limit {
        if bytes[index] == ASCIIByte.lineFeed { return nil }
        if bytes[index] == ASCIIByte.backslash {
            index += min(2, limit - index)
            continue
        }
        if bytes[index] == ASCIIByte.leftParenthesis {
            depth += 1
        } else if bytes[index] == ASCIIByte.rightParenthesis {
            depth -= 1
            if depth == 0 { return index + 1 }
        }
        index += 1
    }
    return nil
}

private func autolinkEnd(bytes: [UInt8], open: Int, limit: Int) -> Int? {
    let start = open + 1
    guard start < limit else { return nil }
    var index = start
    while index < limit && bytes[index] != ASCIIByte.greaterThan && bytes[index] != ASCIIByte.space && bytes[index] != ASCIIByte.lineFeed {
        index += 1
    }
    guard index < limit, bytes[index] == ASCIIByte.greaterThan, index > start else { return nil }
    if hasWebScheme(bytes, start, end: index) || looksLikeEmail(bytes, start, end: index) { return index }
    return nil
}

private func startsWebAddress(_ bytes: [UInt8], _ index: Int, limit: Int) -> Bool {
    let schemes: [[UInt8]] = [
        Array("https://".utf8),
        Array("http://".utf8),
    ]
    for scheme in schemes where index + scheme.count <= limit {
        if Array(bytes[index..<(index + scheme.count)]) == scheme {
            let previous = index > 0 ? bytes[index - 1] : ASCIIByte.space
            if flankingClass(of: previous) != .word { return true }
        }
    }
    return false
}

private func webAddressEnd(_ bytes: [UInt8], _ index: Int, limit: Int) -> Int {
    var end = index
    while end < limit {
        let byte = bytes[end]
        if byte <= ASCIIByte.space || byte == ASCIIByte.lessThan { break }
        end += 1
    }
    while end > index {
        let byte = bytes[end - 1]
        let trailingPunctuation = byte == ASCIIByte.period || byte == ASCIIByte.comma || byte == ASCIIByte.semicolon
            || byte == ASCIIByte.colon || byte == ASCIIByte.exclamationMark || byte == ASCIIByte.questionMark
        if trailingPunctuation {
            end -= 1
            continue
        }
        break
    }
    return end
}

private func hasWebScheme(_ bytes: [UInt8], _ start: Int, end: Int) -> Bool {
    let text = bytes[start..<end]
    let https = Array("https://".utf8)
    let http = Array("http://".utf8)
    if text.count >= https.count && Array(text.prefix(https.count)) == https { return true }
    if text.count >= http.count && Array(text.prefix(http.count)) == http { return true }
    return false
}

private func looksLikeEmail(_ bytes: [UInt8], _ start: Int, end: Int) -> Bool {
    let slice = bytes[start..<end]
    guard let at = slice.firstIndex(of: ASCIIByte.atSign), at > slice.startIndex, at < slice.endIndex - 1 else {
        return false
    }
    return slice[slice.startIndex].isASCIILetter && slice.contains(ASCIIByte.period)
}

private func headingPrefix(bytes: [UInt8], range: Range<Int>) -> (role: HighlightRole, marker: Range<Int>, content: Range<Int>)? {
    var index = range.lowerBound
    let lead = leadingByteCount(bytes, from: index, to: range.upperBound, columnLimit: MarkdownScanLimit.maximumOpeningIndent)
    index += lead
    let hashStart = index
    var hashes = 0
    while index < range.upperBound && bytes[index] == ASCIIByte.hash && hashes < MarkdownScanLimit.maximumHeadingLevel + 1 {
        hashes += 1
        index += 1
    }
    guard (1...6).contains(hashes) else { return nil }
    guard index == range.upperBound || bytes[index].isHorizontalSpace else { return nil }
    let markerEnd = index < range.upperBound ? index + 1 : index
    return (HighlightRole.heading(level: hashes), hashStart..<min(markerEnd, range.upperBound), min(markerEnd, range.upperBound)..<range.upperBound)
}

private func append(
    _ byteRange: Range<Int>,
    role: HighlightRole,
    isSyntax: Bool,
    bytes: [UInt8],
    lines: [TextLine],
    lineHint: TextLine? = nil,
    into spans: inout [HighlightSpan]
) {
    guard byteRange.upperBound > byteRange.lowerBound else { return }
    let sourceLines = lineHint.map { [$0] } ?? lines
    guard let span = RawSpan(byteRange: byteRange, role: role, isSyntax: isSyntax).span(bytes: bytes, lines: sourceLines) else {
        return
    }
    spans.append(span)
}

private func utf16Offset(of byte: Int, bytes: [UInt8], lines: [TextLine]) -> Int {
    guard !lines.isEmpty else { return byte }
    var low = 0
    var high = lines.count
    while low + 1 < high {
        let mid = (low + high) / 2
        if lines[mid].byteStart <= byte { low = mid } else { high = mid }
    }
    let line = lines[low]
    if byte <= line.byteStart { return line.utf16Start }
    if byte >= line.byteEnd { return line.utf16End }
    var byteIndex = line.byteStart
    var utf16Index = line.utf16Start
    while byteIndex < byte && byteIndex < bytes.count {
        let (byteLength, utf16Length) = DocumentBuffer.scalarWidth(bytes, byteIndex)
        if byteLength == 0 { break }
        byteIndex += byteLength
        utf16Index += utf16Length
    }
    return utf16Index
}

private func leadingByteCount(_ bytes: [UInt8], from start: Int, to end: Int, columnLimit: Int) -> Int {
    var index = start
    var columns = 0
    while index < end && columns < columnLimit {
        if bytes[index] == ASCIIByte.space {
            columns += 1
            index += 1
        } else if bytes[index] == ASCIIByte.tab {
            let next = columns + (MarkdownScanLimit.tabColumnWidth - (columns % MarkdownScanLimit.tabColumnWidth))
            if next > columnLimit { break }
            columns = next
            index += 1
        } else {
            break
        }
    }
    return index - start
}

private func trimSpaces(_ bytes: [UInt8], _ range: Range<Int>) -> Range<Int> {
    var lower = range.lowerBound
    var upper = range.upperBound
    while lower < upper && (bytes[lower].isHorizontalSpace) { lower += 1 }
    while upper > lower && (bytes[upper - 1].isHorizontalSpace) { upper -= 1 }
    return lower..<upper
}

private func runLength(_ bytes: [UInt8], _ start: Int, marker: UInt8, limit: Int) -> Int {
    var index = start
    while index < limit && bytes[index] == marker { index += 1 }
    return index - start
}

private func isEscaped(_ bytes: [UInt8], _ index: Int) -> Bool {
    isEscapedByte(bytes, index)
}


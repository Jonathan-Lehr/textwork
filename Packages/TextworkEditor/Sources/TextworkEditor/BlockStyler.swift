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
        kind: StructureKind
    ) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        switch kind {
        case .hashHeading(let level):
            styleHashHeading(bytes: bytes, line: lines[startLine], level: level, into: &spans)
        case .underlineHeading(let level):
            styleUnderlineHeading(bytes: bytes, lines: lines, startLine: startLine, endLine: endLine, level: level, into: &spans)
        case .fence:
            styleFence(bytes: bytes, lines: lines, startLine: startLine, endLine: endLine, into: &spans)
        case .thematic:
            let line = lines[startLine]
            append(line.byteStart..<line.contentByteEnd, role: .thematicBreak, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
        case .quote:
            styleQuote(bytes: bytes, lines: lines, startLine: startLine, endLine: endLine, into: &spans)
        case .list:
            styleList(bytes: bytes, line: lines[startLine], into: &spans)
        case .indentedCode:
            styleIndentedCode(bytes: bytes, lines: lines, startLine: startLine, endLine: endLine, into: &spans)
        case .paragraph:
            let range = contentByteRange(lines: lines, startLine: startLine, endLine: endLine)
            spans.append(contentsOf: InlineStyler.spans(bytes: bytes, range: range, lines: lines))
        case .table:
            styleTable(bytes: bytes, lines: lines, startLine: startLine, endLine: endLine, into: &spans)
        }
        return spans
    }

    static func contentByteRange(lines: [TextLine], startLine: Int, endLine: Int) -> Range<Int> {
        guard startLine < endLine else { return 0..<0 }
        return lines[startLine].byteStart..<lines[endLine - 1].contentByteEnd
    }
}

private enum InlineStyler {
    static func spans(bytes: [UInt8], range: Range<Int>, lines: [TextLine]) -> [HighlightSpan] {
        guard range.lowerBound < range.upperBound else { return [] }
        var raw: [RawSpan] = []
        var mask = ByteMask()
        scanCodeSpans(bytes: bytes, range: range, mask: &mask, into: &raw)
        scanLinksAndImages(bytes: bytes, range: range, mask: &mask, into: &raw)
        scanAutolinks(bytes: bytes, range: range, mask: &mask, into: &raw)
        scanEmphasis(bytes: bytes, range: range, mask: mask, into: &raw)
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

private func styleHashHeading(bytes: [UInt8], line: TextLine, level: Int, into spans: inout [HighlightSpan]) {
    let role = HighlightRole.heading(level: level)
    let sliceStart = line.byteStart
    let sliceEnd = line.contentByteEnd
    let lead = leadingByteCount(bytes, from: sliceStart, to: sliceEnd, columnLimit: 3)
    var index = sliceStart + lead
    let hashStart = index
    while index < sliceEnd && bytes[index] == 0x23 {
        index += 1
    }
    append(hashStart..<index, role: role, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    if index < sliceEnd && (bytes[index] == 0x20 || bytes[index] == 0x09) {
        append(index..<(index + 1), role: role, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
        index += 1
    }
    var contentEnd = sliceEnd
    var trim = sliceEnd
    while trim > index && (bytes[trim - 1] == 0x20 || bytes[trim - 1] == 0x09) {
        trim -= 1
    }
    var hashEnd = trim
    while hashEnd > index && bytes[hashEnd - 1] == 0x23 {
        hashEnd -= 1
    }
    if hashEnd < trim, hashEnd > index, bytes[hashEnd - 1] == 0x20 || bytes[hashEnd - 1] == 0x09 {
        contentEnd = hashEnd - 1
        append(contentEnd..<sliceEnd, role: role, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    }
    if index < contentEnd {
        append(index..<contentEnd, role: role, isSyntax: false, bytes: bytes, lines: [], lineHint: line, into: &spans)
        let inline = InlineStyler.spans(bytes: bytes, range: index..<contentEnd, lines: [line])
        spans.append(contentsOf: inline)
    }
}

private func styleUnderlineHeading(
    bytes: [UInt8],
    lines: [TextLine],
    startLine: Int,
    endLine: Int,
    level: Int,
    into spans: inout [HighlightSpan]
) {
    let role = HighlightRole.heading(level: level)
    let underline = endLine - 1
    if underline > startLine {
        let content = BlockStyler.contentByteRange(lines: lines, startLine: startLine, endLine: underline)
        append(content, role: role, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
        spans.append(contentsOf: InlineStyler.spans(bytes: bytes, range: content, lines: lines))
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
    for lineIndex in startLine..<endLine {
        let line = lines[lineIndex]
        let range = line.byteStart..<line.contentByteEnd
        switch line.kind {
        case .fenceOpen, .fenceClose:
            append(range, role: .codeBlock, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
        default:
            append(range, role: .codeBlock, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
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
        while index < line.contentByteEnd && columns < 4 {
            if bytes[index] == 0x20 {
                columns += 1
                index += 1
            } else if bytes[index] == 0x09 {
                columns += 4 - (columns % 4)
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
    into spans: inout [HighlightSpan]
) {
    for lineIndex in startLine..<endLine {
        let line = lines[lineIndex]
        var index = line.byteStart
        let limit = line.contentByteEnd
        let lead = leadingByteCount(bytes, from: index, to: limit, columnLimit: 3)
        index += lead
        while index < limit && bytes[index] == 0x3E {
            let markerStart = index
            index += 1
            if index < limit && bytes[index] == 0x20 {
                index += 1
            }
            append(markerStart..<index, role: .blockQuote, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
        }
        if index < limit {
            let content = index..<limit
            if let heading = headingPrefix(bytes: bytes, range: content) {
                append(heading.marker, role: heading.role, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
                if heading.content.lowerBound < heading.content.upperBound {
                    append(heading.content, role: heading.role, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
                    spans.append(contentsOf: InlineStyler.spans(bytes: bytes, range: heading.content, lines: lines))
                }
            } else {
                spans.append(contentsOf: InlineStyler.spans(bytes: bytes, range: content, lines: lines))
            }
        }
    }
}

private func styleList(bytes: [UInt8], line: TextLine, into spans: inout [HighlightSpan]) {
    let limit = line.contentByteEnd
    var index = line.byteStart
    index += leadingByteCount(bytes, from: index, to: limit, columnLimit: 3)
    let markerStart = index
    if index < limit && (bytes[index] == 0x2D || bytes[index] == 0x2B || bytes[index] == 0x2A) {
        index += 1
    } else {
        while index < limit && bytes[index].isASCIIDigit {
            index += 1
        }
        if index < limit && (bytes[index] == 0x2E || bytes[index] == 0x29) {
            index += 1
        }
    }
    while index < limit && (bytes[index] == 0x20 || bytes[index] == 0x09) {
        index += 1
        break
    }
    if index + 2 < limit, bytes[index] == 0x5B, bytes[index + 2] == 0x5D {
        let checkbox = bytes[index + 1]
        if checkbox == 0x20 || checkbox == 0x78 || checkbox == 0x58 {
            index += 3
            if index < limit && (bytes[index] == 0x20 || bytes[index] == 0x09) {
                index += 1
            }
        }
    }
    append(markerStart..<index, role: .listMarker, isSyntax: true, bytes: bytes, lines: [], lineHint: line, into: &spans)
    if index < limit {
        spans.append(contentsOf: InlineStyler.spans(bytes: bytes, range: index..<limit, lines: [line]))
    }
}

private func styleTable(
    bytes: [UInt8],
    lines: [TextLine],
    startLine: Int,
    endLine: Int,
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
            case .pipe(let range):
                append(range, role: .table, isSyntax: true, bytes: bytes, lines: lines, into: &spans)
            case .text(let range):
                append(range, role: .table, isSyntax: false, bytes: bytes, lines: lines, into: &spans)
                spans.append(contentsOf: InlineStyler.spans(bytes: bytes, range: range, lines: lines))
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
        if bytes[index] == 0x5C, index + 1 < limit {
            index += 2
            continue
        }
        if bytes[index] == 0x7C {
            let trimmed = trimSpaces(bytes, textStart..<index)
            if !trimmed.isEmpty {
                cells.append(.text(trimmed))
            }
            cells.append(.pipe(index..<(index + 1)))
            index += 1
            textStart = index
            continue
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
    let trimmed = trimSpaces(bytes, textStart..<limit)
    if !trimmed.isEmpty {
        cells.append(.text(trimmed))
    }
    return cells
}

private func scanCodeSpans(bytes: [UInt8], range: Range<Int>, mask: inout ByteMask, into raw: inout [RawSpan]) {
    var index = range.lowerBound
    while index < range.upperBound {
        if bytes[index] != 0x60 || isEscaped(bytes, index) {
            index += DocumentBuffer.scalarWidth(bytes, index).0
            continue
        }
        let openerLength = runLength(bytes, index, marker: 0x60, limit: range.upperBound)
        var cursor = index + openerLength
        var closer: Int?
        while cursor < range.upperBound {
            if bytes[cursor] == 0x60 && !isEscaped(bytes, cursor) {
                let length = runLength(bytes, cursor, marker: 0x60, limit: range.upperBound)
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
        if !content.isEmpty {
            raw.append(RawSpan(byteRange: content, role: .codeSpan, isSyntax: false))
        }
        raw.append(RawSpan(byteRange: closer..<(closer + openerLength), role: .codeSpan, isSyntax: true))
        mask.cover(index..<(closer + openerLength))
        index = closer + openerLength
    }
}

private func scanLinksAndImages(
    bytes: [UInt8],
    range: Range<Int>,
    mask: inout ByteMask,
    into raw: inout [RawSpan]
) {
    var index = range.lowerBound
    while index < range.upperBound {
        if let end = mask.endOfCover(containing: index) {
            index = end
            continue
        }
        let isImage = bytes[index] == 0x21 && index + 1 < range.upperBound && bytes[index + 1] == 0x5B && !isEscaped(bytes, index)
        let isLink = bytes[index] == 0x5B && !isEscaped(bytes, index)
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
        guard afterLabel < range.upperBound, bytes[afterLabel] == 0x28 else {
            index += 1
            continue
        }
        guard let destinationEnd = closingParenthesis(bytes: bytes, from: afterLabel + 1, limit: range.upperBound) else {
            index += 1
            continue
        }
        if isImage {
            raw.append(RawSpan(byteRange: index..<(index + 1), role: role, isSyntax: true))
        }
        raw.append(RawSpan(byteRange: bracket..<(bracket + 1), role: role, isSyntax: true))
        let label = (bracket + 1)..<labelEnd
        if !label.isEmpty {
            raw.append(RawSpan(byteRange: label, role: role, isSyntax: false))
            let labelSpans = emphasisSpans(bytes: bytes, range: label, mask: mask)
            raw.append(contentsOf: labelSpans)
        }
        raw.append(RawSpan(byteRange: labelEnd..<destinationEnd, role: role, isSyntax: true))
        mask.cover(index..<destinationEnd)
        index = destinationEnd
    }
}

private func scanAutolinks(bytes: [UInt8], range: Range<Int>, mask: inout ByteMask, into raw: inout [RawSpan]) {
    var index = range.lowerBound
    while index < range.upperBound {
        if let end = mask.endOfCover(containing: index) {
            index = end
            continue
        }
        if bytes[index] == 0x3C && !isEscaped(bytes, index) {
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
        if (marker == 0x2A || marker == 0x5F), !isEscaped(bytes, index) {
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
                if !content.isEmpty {
                    spans.append(RawSpan(byteRange: content, role: role, isSyntax: false))
                }
                spans.append(RawSpan(byteRange: closerByte..<(closerByte + used), role: role, isSyntax: true))
                delimiters[openerIndex].remaining -= used
                delimiters[closerIndex].startByte += used
                delimiters[closerIndex].remaining -= used
                matched = true
                break
            }
            openerIndex -= 1
        }
        if !matched || delimiters[closerIndex].remaining == 0 {
            closerIndex += 1
        }
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
    if marker == 0x5F {
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
    case 0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C:
        return .whitespace
    case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E:
        return .punctuation
    default:
        return .word
    }
}

private func closingBracket(bytes: [UInt8], from start: Int, limit: Int, mask: ByteMask) -> Int? {
    var index = start
    while index < limit {
        if let end = mask.endOfCover(containing: index) {
            index = end
            continue
        }
        if bytes[index] == 0x5D && !isEscaped(bytes, index) {
            return index
        }
        if bytes[index] == 0x0A || bytes[index] == 0x5B {
            return nil
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
    return nil
}

private func closingParenthesis(bytes: [UInt8], from start: Int, limit: Int) -> Int? {
    var index = start
    var depth = 1
    while index < limit {
        if bytes[index] == 0x0A { return nil }
        if bytes[index] == 0x5C {
            index += min(2, limit - index)
            continue
        }
        if bytes[index] == 0x28 {
            depth += 1
        } else if bytes[index] == 0x29 {
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
    while index < limit && bytes[index] != 0x3E && bytes[index] != 0x20 && bytes[index] != 0x0A {
        index += 1
    }
    guard index < limit, bytes[index] == 0x3E, index > start else { return nil }
    if hasWebScheme(bytes, start, end: index) || looksLikeEmail(bytes, start, end: index) {
        return index
    }
    return nil
}

private func startsWebAddress(_ bytes: [UInt8], _ index: Int, limit: Int) -> Bool {
    let schemes: [[UInt8]] = [
        Array("https://".utf8),
        Array("http://".utf8),
    ]
    for scheme in schemes where index + scheme.count <= limit {
        if Array(bytes[index..<(index + scheme.count)]) == scheme {
            let previous = index > 0 ? bytes[index - 1] : 0x20
            if flankingClass(of: previous) != .word {
                return true
            }
        }
    }
    return false
}

private func webAddressEnd(_ bytes: [UInt8], _ index: Int, limit: Int) -> Int {
    var end = index
    while end < limit {
        let byte = bytes[end]
        if byte <= 0x20 || byte == 0x3C { break }
        end += 1
    }
    while end > index {
        let byte = bytes[end - 1]
        if byte == 0x2E || byte == 0x2C || byte == 0x3B || byte == 0x3A || byte == 0x21 || byte == 0x3F {
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
    guard let at = slice.firstIndex(of: 0x40), at > slice.startIndex, at < slice.endIndex - 1 else { return false }
    return slice[slice.startIndex].isASCIILetter && slice.contains(0x2E)
}

private func headingPrefix(bytes: [UInt8], range: Range<Int>) -> (role: HighlightRole, marker: Range<Int>, content: Range<Int>)? {
    var index = range.lowerBound
    let lead = leadingByteCount(bytes, from: index, to: range.upperBound, columnLimit: 3)
    index += lead
    let hashStart = index
    var hashes = 0
    while index < range.upperBound && bytes[index] == 0x23 && hashes < 7 {
        hashes += 1
        index += 1
    }
    guard (1...6).contains(hashes) else { return nil }
    guard index == range.upperBound || bytes[index] == 0x20 || bytes[index] == 0x09 else { return nil }
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
    guard let span = RawSpan(byteRange: byteRange, role: role, isSyntax: isSyntax).span(bytes: bytes, lines: sourceLines) else { return }
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
        if bytes[index] == 0x20 {
            columns += 1
            index += 1
        } else if bytes[index] == 0x09 {
            let next = columns + (4 - (columns % 4))
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
    while lower < upper && (bytes[lower] == 0x20 || bytes[lower] == 0x09) { lower += 1 }
    while upper > lower && (bytes[upper - 1] == 0x20 || bytes[upper - 1] == 0x09) { upper -= 1 }
    return lower..<upper
}

private func runLength(_ bytes: [UInt8], _ start: Int, marker: UInt8, limit: Int) -> Int {
    var index = start
    while index < limit && bytes[index] == marker { index += 1 }
    return index - start
}

private func isEscaped(_ bytes: [UInt8], _ index: Int) -> Bool {
    var slashCount = 0
    var cursor = index - 1
    while cursor >= 0 && bytes[cursor] == 0x5C {
        slashCount += 1
        cursor -= 1
    }
    return slashCount % 2 == 1
}

private extension UInt8 {
    var isASCIIDigit: Bool { self >= 0x30 && self <= 0x39 }
    var isASCIILetter: Bool {
        (self >= 0x41 && self <= 0x5A) || (self >= 0x61 && self <= 0x7A)
    }
}

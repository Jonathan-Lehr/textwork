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
}

struct StyledBlock: Equatable, Sendable {
    var startLine: Int
    var endLine: Int
    var kind: StructureKind
    var spans: [HighlightSpan]
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
            if byte == 0x0A || byte == 0x0D {
                let newlineBytes = (byte == 0x0D && byteIndex + 1 < bytes.count && bytes[byteIndex + 1] == 0x0A) ? 2 : 1
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
        while index < count {
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
            lines[index].kind = .paragraph
            if index + 1 < count, let _ = underlineHeadingLevel(lines[index + 1], bytes: bytes) {
                lines[index + 1].kind = .underlineMarker
                index += 2
                continue
            }
            index += 1
        }
    }

    static func group(_ lines: [TextLine], bytes: [UInt8]) -> [(start: Int, end: Int, kind: StructureKind)] {
        var blocks: [(start: Int, end: Int, kind: StructureKind)] = []
        var index = 0
        while index < lines.count {
            switch lines[index].kind {
            case .blank:
                index += 1
            case .hashHeading:
                let level = hashHeadingLevel(lines[index], bytes: bytes)
                blocks.append((index, index + 1, .hashHeading(level: level)))
                index += 1
            case .fenceOpen:
                var end = index + 1
                while end < lines.count && lines[end].kind == .fenceInside {
                    end += 1
                }
                if end < lines.count && lines[end].kind == .fenceClose {
                    end += 1
                }
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
        while index < slice.endIndex && slice[index] == 0x23 && hashes < 6 {
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
        if target >= line.utf16End {
            return bytes.count
        }
        var byteIndex = line.byteStart
        var utf16 = line.utf16Start
        let limit = line.byteEnd
        while byteIndex < limit && utf16 < target {
            let (byteLength, utf16Length) = scalarWidth(bytes, byteIndex)
            if utf16 + utf16Length > target {
                break
            }
            byteIndex += byteLength
            utf16 += utf16Length
        }
        return byteIndex
    }

    static func lineIndex(containingUTF16 target: Int, lines: [TextLine]) -> Int {
        if lines.isEmpty { return 0 }
        if target <= 0 { return 0 }
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
        if low < lines.count - 1 && target >= lines[low].utf16End {
            return low + 1
        }
        return low
    }

    static func scalarWidth(_ bytes: [UInt8], _ index: Int) -> (Int, Int) {
        guard index < bytes.count else { return (0, 0) }
        let byte = bytes[index]
        if byte < 0x80 { return (1, 1) }
        if byte & 0xE0 == 0xC0 { return (min(2, bytes.count - index), 1) }
        if byte & 0xF0 == 0xE0 { return (min(3, bytes.count - index), 1) }
        if byte & 0xF8 == 0xF0 { return (min(4, bytes.count - index), 2) }
        return (1, 1)
    }
}

// MARK: - Line predicates

private func content(_ line: TextLine, _ bytes: [UInt8]) -> ArraySlice<UInt8> {
    bytes[line.byteStart..<line.contentByteEnd]
}

private func isBlank(_ line: TextLine, bytes: [UInt8]) -> Bool {
    for byte in content(line, bytes) {
        if byte != 0x20 && byte != 0x09 { return false }
    }
    return true
}

private func leadingWhitespace(_ slice: ArraySlice<UInt8>) -> (columns: Int, bytes: Int) {
    var columns = 0
    var count = 0
    for byte in slice {
        if byte == 0x20 {
            columns += 1
            count += 1
        } else if byte == 0x09 {
            columns += 4 - (columns % 4)
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
    if lead.columns > 3 { return false }
    var index = slice.startIndex + lead.bytes
    var hashes = 0
    while index < slice.endIndex && slice[index] == 0x23 && hashes < 7 {
        hashes += 1
        index += 1
    }
    guard (1...6).contains(hashes) else { return false }
    if index == slice.endIndex { return true }
    return slice[index] == 0x20 || slice[index] == 0x09
}

private func openingFence(_ line: TextLine, bytes: [UInt8]) -> (marker: UInt8, length: Int)? {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > 3 { return nil }
    var index = slice.startIndex + lead.bytes
    guard index < slice.endIndex else { return nil }
    let marker = slice[index]
    guard marker == 0x60 || marker == 0x7E else { return nil }
    var length = 0
    while index < slice.endIndex && slice[index] == marker {
        length += 1
        index += 1
    }
    guard length >= 3 else { return nil }
    if marker == 0x60 {
        while index < slice.endIndex {
            if slice[index] == 0x60 { return nil }
            index += 1
        }
    }
    return (marker, length)
}

private func fenceCloser(_ line: TextLine, bytes: [UInt8], marker: UInt8, minimum: Int) -> Bool {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > 3 { return false }
    var index = slice.startIndex + lead.bytes
    var length = 0
    while index < slice.endIndex && slice[index] == marker {
        length += 1
        index += 1
    }
    guard length >= minimum else { return false }
    while index < slice.endIndex {
        let byte = slice[index]
        if byte != 0x20 && byte != 0x09 { return false }
        index += 1
    }
    return true
}

private func isThematic(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > 3 { return false }
    var index = slice.startIndex + lead.bytes
    guard index < slice.endIndex else { return false }
    let marker = slice[index]
    guard marker == 0x2A || marker == 0x2D || marker == 0x5F else { return false }
    var count = 0
    while index < slice.endIndex {
        let byte = slice[index]
        if byte == marker {
            count += 1
        } else if byte != 0x20 && byte != 0x09 {
            return false
        }
        index += 1
    }
    return count >= 3
}

private func underlineHeadingLevel(_ line: TextLine, bytes: [UInt8]) -> Int? {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > 3 { return nil }
    var index = slice.startIndex + lead.bytes
    guard index < slice.endIndex else { return nil }
    let marker = slice[index]
    guard marker == 0x3D || marker == 0x2D else { return nil }
    while index < slice.endIndex && slice[index] == marker {
        index += 1
    }
    while index < slice.endIndex {
        let byte = slice[index]
        if byte != 0x20 && byte != 0x09 { return nil }
        index += 1
    }
    return marker == 0x3D ? 1 : 2
}

private func isQuote(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > 3 { return false }
    let index = slice.startIndex + lead.bytes
    return index < slice.endIndex && slice[index] == 0x3E
}

private func isList(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let slice = content(line, bytes)
    let lead = leadingWhitespace(slice)
    if lead.columns > 3 { return false }
    var index = slice.startIndex + lead.bytes
    guard index < slice.endIndex else { return false }
    let byte = slice[index]
    if byte == 0x2D || byte == 0x2B || byte == 0x2A {
        let next = index + 1
        if next >= slice.endIndex { return true }
        return slice[next] == 0x20 || slice[next] == 0x09
    }
    var digits = 0
    while index < slice.endIndex && slice[index].isDigit && digits < 9 {
        digits += 1
        index += 1
    }
    guard digits > 0, index < slice.endIndex else { return false }
    let suffix = slice[index]
    guard suffix == 0x2E || suffix == 0x29 else { return false }
    let next = index + 1
    if next >= slice.endIndex { return true }
    return slice[next] == 0x20 || slice[next] == 0x09
}

private func isIndentedCode(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let lead = leadingWhitespace(content(line, bytes))
    return lead.columns >= 4 && !isBlank(line, bytes: bytes)
}

private func containsPipe(_ line: TextLine, bytes: [UInt8]) -> Bool {
    content(line, bytes).contains(0x7C)
}

private func isTableDelimiter(_ line: TextLine, bytes: [UInt8]) -> Bool {
    let slice = content(line, bytes)
    var index = slice.startIndex
    var sawCell = false
    var sawPipe = false
    func skipSpace() {
        while index < slice.endIndex && (slice[index] == 0x20 || slice[index] == 0x09) {
            index += 1
        }
    }
    skipSpace()
    if index < slice.endIndex && slice[index] == 0x7C {
        sawPipe = true
        index += 1
    }
    while index < slice.endIndex {
        skipSpace()
        if index < slice.endIndex && slice[index] == 0x3A { index += 1 }
        var dashes = 0
        while index < slice.endIndex && slice[index] == 0x2D {
            dashes += 1
            index += 1
        }
        if dashes == 0 { return false }
        if index < slice.endIndex && slice[index] == 0x3A { index += 1 }
        skipSpace()
        sawCell = true
        if index < slice.endIndex && slice[index] == 0x7C {
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

private extension UInt8 {
    var isDigit: Bool { self >= 0x30 && self <= 0x39 }
}

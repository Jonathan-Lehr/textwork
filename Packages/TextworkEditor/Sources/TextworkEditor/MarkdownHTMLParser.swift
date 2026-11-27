enum MarkdownBlock {
    case heading(level: Int, inlines: [MarkdownInline])
    case paragraph(inlines: [MarkdownInline])
    case codeBlock(language: String?, text: String)
    case blockQuote(children: [MarkdownBlock])
    case list(orderedStart: Int?, tight: Bool, items: [MarkdownListItem])
    case table(alignments: [MarkdownTableAlignment], header: [MarkdownTableCell], rows: [[MarkdownTableCell]])
    case thematicBreak
}

struct MarkdownListItem {
    var checked: Bool?
    var children: [MarkdownBlock]
}

enum MarkdownTableAlignment {
    case none
    case left
    case center
    case right
}

struct MarkdownTableCell {
    var inlines: [MarkdownInline]
}

struct UnresolvedReference {
    /// Labels in priority order. The first one present in the definition map wins.
    var labels: [String]
    /// Literal text that follows the link when the label at the same index matches.
    /// A full reference that misses falls back to a shortcut and leaves `[label]` behind.
    var trailingAfterMatch: [String]
    var children: [MarkdownInline]
    var isImage: Bool
    var opening: String
    var closing: String
}

enum MarkdownInline {
    case text(String)
    case softBreak
    case hardBreak
    case code(String)
    case emphasis(children: [MarkdownInline])
    case strong(children: [MarkdownInline])
    case link(destination: String, title: String?, children: [MarkdownInline])
    case image(destination: String, alternativeText: String)
    case unresolvedReference(UnresolvedReference)
}

enum MarkdownHTMLParser {
    static func blocks(in markdown: String) -> [MarkdownBlock] {
        let definitions = ReferenceDefinitionMap()
        var parser = BlockParser(lines: splitLines(markdown), definitions: definitions)
        let blocks = parser.parseBlocks(until: parser.lines.count)
        return resolveReferences(in: blocks, definitions: definitions)
    }
}

final class ReferenceDefinitionMap {
    var values: [String: (destination: String, title: String?)] = [:]

    func add(label: String, destination: String, title: String?) {
        let key = normalizeReferenceLabel(label)
        guard !key.isEmpty, values[key] == nil else { return }
        values[key] = (destination, title)
    }
}

enum MarkdownInlineParser {
    static func parse(_ text: String) -> [MarkdownInline] {
        InlineParser(text: text).parse(allowLinks: true)
    }
}

private struct BlockParser {
    var lines: [String]
    var index = 0
    var definitions: ReferenceDefinitionMap

    mutating func parseBlocks(until end: Int) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        while index < end {
            let start = index
            while index < end, isBlank(lines[index]) {
                index += 1
            }
            if index >= end { break }
            if takeReferenceDefinition() {
                continue
            }
            if let fence = takeFence(until: end) {
                blocks.append(fence)
            } else if let heading = takeATXHeading() {
                blocks.append(heading)
            } else if let table = takeTable(until: end) {
                blocks.append(table)
            } else if isThematicBreak(lines[index]) {
                blocks.append(.thematicBreak)
                index += 1
            } else if isBlockQuoteLine(lines[index]) {
                blocks.append(takeBlockQuote(until: end))
            } else if listMarker(lines[index]) != nil {
                blocks.append(takeList(until: end))
            } else if leadingColumnCount(lines[index]) >= 4 {
                blocks.append(takeIndentedCode(until: end))
            } else {
                blocks.append(takeParagraph(until: end))
            }
            if index == start {
                index += 1
            }
        }
        return blocks
    }

    mutating func takeFence(until end: Int) -> MarkdownBlock? {
        guard let opening = fenceOpening(lines[index]) else { return nil }
        index += 1
        var content: [String] = []
        while index < end {
            if fenceCloses(lines[index], marker: opening.marker, minimum: opening.length) {
                index += 1
                break
            }
            content.append(stripColumns(lines[index], opening.indent))
            index += 1
        }
        var text = content.joined(separator: "\n")
        if !content.isEmpty {
            text += "\n"
        }
        return .codeBlock(language: languageName(opening.info), text: text)
    }

    mutating func takeATXHeading() -> MarkdownBlock? {
        guard let heading = atxHeading(lines[index]) else { return nil }
        index += 1
        return .heading(level: heading.level, inlines: MarkdownInlineParser.parse(heading.content))
    }

    mutating func takeTable(until end: Int) -> MarkdownBlock? {
        guard index + 1 < end else { return nil }
        let headerLine = lines[index]
        guard containsUnescapedPipe(headerLine), let alignments = tableDelimiter(lines[index + 1]) else {
            return nil
        }
        let headerCells = tableCells(headerLine)
        guard headerCells.count == alignments.count, !headerCells.isEmpty else { return nil }
        index += 2
        var rows: [[MarkdownTableCell]] = []
        while index < end {
            let line = lines[index]
            if isBlank(line) || !containsUnescapedPipe(line) { break }
            if fenceOpening(line) != nil || atxHeading(line) != nil || isBlockQuoteLine(line) { break }
            let cells = tableCells(line)
            let row = (0..<headerCells.count).map { column -> MarkdownTableCell in
                let source = column < cells.count ? cells[column] : ""
                return MarkdownTableCell(inlines: MarkdownInlineParser.parse(source))
            }
            rows.append(row)
            index += 1
        }
        let header = headerCells.map { MarkdownTableCell(inlines: MarkdownInlineParser.parse($0)) }
        return .table(alignments: alignments, header: header, rows: rows)
    }

    mutating func takeBlockQuote(until end: Int) -> MarkdownBlock {
        var inner: [String] = []
        while index < end {
            let line = lines[index]
            if isBlank(line) {
                if index + 1 < end, isBlockQuoteLine(lines[index + 1]) {
                    inner.append("")
                    index += 1
                    continue
                }
                break
            }
            if isBlockQuoteLine(line) {
                inner.append(stripBlockQuoteMarker(line))
                index += 1
                continue
            }
            if !interruptsParagraph(line) {
                inner.append(line)
                index += 1
                continue
            }
            break
        }
        let children = parseNested(inner.joined(separator: "\n"))
        return .blockQuote(children: children)
    }

    mutating func takeList(until end: Int) -> MarkdownBlock {
        guard let first = listMarker(lines[index]) else {
            index += 1
            return .paragraph(inlines: [])
        }
        let markerIndent = first.indent
        let ordered = first.orderedStart != nil
        let delimiter = first.orderedDelimiter
        let startNumber = first.orderedStart
        var items: [MarkdownListItem] = []
        var loose = false

        while index < end {
            guard let marker = listMarker(lines[index]),
                  marker.indent == markerIndent,
                  (marker.orderedStart != nil) == ordered,
                  !ordered || marker.orderedDelimiter == delimiter
            else { break }
            var itemLines = [marker.remainder]
            let contentColumn = marker.contentColumn
            let checked = marker.checked
            index += 1
            var blankRun: [String] = []
            while index < end {
                let line = lines[index]
                if isBlank(line) {
                    blankRun.append("")
                    index += 1
                    continue
                }
                if let next = listMarker(line) {
                    let sameList = next.indent == markerIndent
                        && (next.orderedStart != nil) == ordered
                        && (!ordered || next.orderedDelimiter == delimiter)
                    if sameList {
                        if !blankRun.isEmpty { loose = true }
                        break
                    }
                    if next.indent <= markerIndent {
                        break
                    }
                }
                let indent = leadingColumnCount(line)
                let nestedMarker = listMarker(line)?.indent ?? -1
                if indent >= contentColumn || nestedMarker > markerIndent {
                    if !blankRun.isEmpty {
                        loose = true
                        itemLines.append(contentsOf: blankRun)
                        blankRun.removeAll()
                    }
                    itemLines.append(stripColumns(line, contentColumn))
                    index += 1
                    continue
                }
                if blankRun.isEmpty, !interruptsParagraph(line) {
                    itemLines.append(line)
                    index += 1
                    continue
                }
                break
            }
            let children = parseNested(itemLines.joined(separator: "\n"))
            items.append(MarkdownListItem(checked: checked, children: children))
        }
        return .list(orderedStart: ordered ? startNumber : nil, tight: !loose, items: items)
    }

    mutating func takeIndentedCode(until end: Int) -> MarkdownBlock {
        var content: [String] = []
        var blanks: [String] = []
        while index < end {
            let line = lines[index]
            if isBlank(line) {
                blanks.append("")
                index += 1
                continue
            }
            if leadingColumnCount(line) >= 4 {
                content.append(contentsOf: blanks)
                blanks.removeAll()
                content.append(stripColumns(line, 4))
                index += 1
                continue
            }
            break
        }
        var text = content.joined(separator: "\n")
        if !content.isEmpty {
            text += "\n"
        }
        return .codeBlock(language: nil, text: text)
    }

    mutating func takeParagraph(until end: Int) -> MarkdownBlock {
        var collected = [lines[index]]
        index += 1
        while index < end {
            let line = lines[index]
            if isBlank(line) { break }
            if let level = setextLevel(line) {
                index += 1
                let text = collected.joined(separator: "\n")
                return .heading(level: level, inlines: MarkdownInlineParser.parse(text))
            }
            if interruptsParagraph(line) { break }
            collected.append(line)
            index += 1
        }
        return .paragraph(inlines: MarkdownInlineParser.parse(collected.joined(separator: "\n")))
    }

    mutating func takeReferenceDefinition() -> Bool {
        guard let parsed = parseReferenceDefinition(lines[index]) else { return false }
        definitions.add(label: parsed.label, destination: parsed.destination, title: parsed.title)
        index += 1
        return true
    }

    func parseNested(_ source: String) -> [MarkdownBlock] {
        var parser = BlockParser(lines: splitLines(source), definitions: definitions)
        return parser.parseBlocks(until: parser.lines.count)
    }
}

private struct ListMarkerMatch {
    var indent: Int
    var contentColumn: Int
    var orderedStart: Int?
    var orderedDelimiter: Character?
    var checked: Bool?
    var remainder: String
}

private struct FenceOpening {
    var marker: Character
    var length: Int
    var indent: Int
    var info: String
}

private func splitLines(_ markdown: String) -> [String] {
    if markdown.isEmpty { return [] }
    var lines: [String] = []
    var current = ""
    let scalars = markdown.unicodeScalars
    var index = scalars.startIndex
    while index < scalars.endIndex {
        let scalar = scalars[index]
        if scalar == "\n" || scalar == "\r" {
            lines.append(current)
            current = ""
            let next = scalars.index(after: index)
            if scalar == "\r", next < scalars.endIndex, scalars[next] == "\n" {
                index = scalars.index(after: next)
            } else {
                index = next
            }
            continue
        }
        current.unicodeScalars.append(scalar)
        index = scalars.index(after: index)
    }
    if !current.isEmpty {
        lines.append(current)
    }
    return lines
}

private func isBlank(_ line: String) -> Bool {
    line.allSatisfy { $0 == " " || $0 == "\t" }
}

private func leadingColumnCount(_ line: String) -> Int {
    var column = 0
    for character in line {
        if character == " " {
            column += 1
        } else if character == "\t" {
            column += 4 - (column % 4)
        } else {
            break
        }
    }
    return column
}

private func stripColumns(_ line: String, _ columns: Int) -> String {
    var remaining = columns
    var column = 0
    var index = line.startIndex
    while index < line.endIndex, remaining > 0 {
        if line[index] == " " {
            remaining -= 1
            column += 1
            index = line.index(after: index)
        } else if line[index] == "\t" {
            let width = 4 - (column % 4)
            if width > remaining {
                let leftover = width - remaining
                return String(repeating: " ", count: leftover) + line[line.index(after: index)...]
            }
            remaining -= width
            column += width
            index = line.index(after: index)
        } else {
            break
        }
    }
    return String(line[index...])
}

private func isThematicBreak(_ line: String) -> Bool {
    let indent = leadingColumnCount(line)
    if indent >= 4 { return false }
    let content = stripColumns(line, indent)
    guard let marker = content.first(where: { $0 != " " && $0 != "\t" }) else { return false }
    guard marker == "-" || marker == "*" || marker == "_" else { return false }
    var count = 0
    for character in content {
        if character == marker {
            count += 1
        } else if character != " " && character != "\t" {
            return false
        }
    }
    return count >= 3
}

private func setextLevel(_ line: String) -> Int? {
    let indent = leadingColumnCount(line)
    if indent >= 4 { return nil }
    let content = stripColumns(line, indent)
    guard let marker = content.first, marker == "=" || marker == "-" else { return nil }
    var index = content.startIndex
    while index < content.endIndex, content[index] == marker {
        index = content.index(after: index)
    }
    guard index > content.startIndex else { return nil }
    while index < content.endIndex {
        if content[index] != " " && content[index] != "\t" { return nil }
        index = content.index(after: index)
    }
    return marker == "=" ? 1 : 2
}

private func atxHeading(_ line: String) -> (level: Int, content: String)? {
    let indent = leadingColumnCount(line)
    if indent >= 4 { return nil }
    var content = stripColumns(line, indent)
    var level = 0
    while content.first == "#", level < 7 {
        content.removeFirst()
        level += 1
    }
    guard (1...6).contains(level) else { return nil }
    if let first = content.first, first != " ", first != "\t" { return nil }
    while content.first == " " || content.first == "\t" {
        content.removeFirst()
    }
    while content.last == " " || content.last == "\t" {
        content.removeLast()
    }
    if content.last == "#" {
        var closing = 0
        var end = content.endIndex
        while end > content.startIndex {
            let previous = content.index(before: end)
            if content[previous] != "#" { break }
            closing += 1
            end = previous
        }
        if closing > 0, end > content.startIndex {
            let before = content.index(before: end)
            if content[before] == " " || content[before] == "\t" {
                content = String(content[..<before])
                while content.last == " " || content.last == "\t" {
                    content.removeLast()
                }
            }
        } else if closing > 0, end == content.startIndex {
            content = ""
        }
    }
    return (level, content)
}

private func fenceOpening(_ line: String) -> FenceOpening? {
    let indent = leadingColumnCount(line)
    if indent >= 4 { return nil }
    let content = stripColumns(line, indent)
    guard let marker = content.first, marker == "`" || marker == "~" else { return nil }
    var length = 0
    var index = content.startIndex
    while index < content.endIndex, content[index] == marker {
        length += 1
        index = content.index(after: index)
    }
    guard length >= 3 else { return nil }
    let info = content[index...].trimmingCharacters(in: .whitespaces)
    if marker == "`", info.contains("`") { return nil }
    return FenceOpening(marker: marker, length: length, indent: indent, info: info)
}

private func fenceCloses(_ line: String, marker: Character, minimum: Int) -> Bool {
    let indent = leadingColumnCount(line)
    if indent >= 4 { return false }
    let content = stripColumns(line, indent)
    var length = 0
    var index = content.startIndex
    while index < content.endIndex, content[index] == marker {
        length += 1
        index = content.index(after: index)
    }
    guard length >= minimum else { return false }
    while index < content.endIndex {
        if content[index] != " " && content[index] != "\t" { return false }
        index = content.index(after: index)
    }
    return true
}

private func languageName(_ info: String) -> String? {
    let word = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
    guard !word.isEmpty else { return nil }
    let allowed = word.allSatisfy { character in
        isASCIILetter(character) || character.isNumber || character == "_" || character == "+" || character == "-" || character == "."
    }
    return allowed ? word : nil
}

private func isBlockQuoteLine(_ line: String) -> Bool {
    let indent = leadingColumnCount(line)
    if indent >= 4 { return false }
    return stripColumns(line, indent).first == ">"
}

private func stripBlockQuoteMarker(_ line: String) -> String {
    let indent = min(leadingColumnCount(line), 3)
    var content = stripColumns(line, indent)
    guard content.first == ">" else { return content }
    content.removeFirst()
    if content.first == " " {
        content.removeFirst()
    }
    return content
}

private func interruptsParagraph(_ line: String) -> Bool {
    if isBlank(line) || fenceOpening(line) != nil || atxHeading(line) != nil || isThematicBreak(line) || isBlockQuoteLine(line) {
        return true
    }
    if let marker = listMarker(line) {
        if marker.orderedStart == nil { return true }
        return marker.orderedStart == 1
    }
    return false
}

private func listMarker(_ line: String) -> ListMarkerMatch? {
    if isThematicBreak(line) { return nil }
    let indent = leadingColumnCount(line)
    if indent >= 4 { return nil }
    let rest = stripColumns(line, indent)
    guard let first = rest.first else { return nil }
    var column = indent
    var index = rest.startIndex
    var orderedStart: Int?
    var orderedDelimiter: Character?

    if first == "-" || first == "+" || first == "*" {
        column += 1
        index = rest.index(after: index)
    } else if first.isNumber {
        var digits = 0
        var value = 0
        while index < rest.endIndex, rest[index].isNumber, digits < 9 {
            value = value * 10 + (rest[index].wholeNumberValue ?? 0)
            digits += 1
            column += 1
            index = rest.index(after: index)
        }
        guard digits > 0, index < rest.endIndex else { return nil }
        let delimiter = rest[index]
        guard delimiter == "." || delimiter == ")" else { return nil }
        orderedStart = value
        orderedDelimiter = delimiter
        column += 1
        index = rest.index(after: index)
    } else {
        return nil
    }

    if index >= rest.endIndex {
        return ListMarkerMatch(
            indent: indent,
            contentColumn: column + 1,
            orderedStart: orderedStart,
            orderedDelimiter: orderedDelimiter,
            checked: nil,
            remainder: ""
        )
    }
    guard rest[index] == " " || rest[index] == "\t" else { return nil }
    if rest[index] == " " {
        column += 1
    } else {
        column += 4 - (column % 4)
    }
    index = rest.index(after: index)

    var checked: Bool?
    if index < rest.endIndex, rest[index] == "[" {
        let markIndex = rest.index(after: index)
        if markIndex < rest.endIndex {
            let mark = rest[markIndex]
            let closeIndex = rest.index(after: markIndex)
            if closeIndex < rest.endIndex, rest[closeIndex] == "]", mark == " " || mark == "x" || mark == "X" {
                let after = rest.index(after: closeIndex)
                if after >= rest.endIndex || rest[after] == " " || rest[after] == "\t" {
                    checked = mark == "x" || mark == "X"
                    column += 3
                    index = after
                    if index < rest.endIndex, rest[index] == " " || rest[index] == "\t" {
                        if rest[index] == " " {
                            column += 1
                        } else {
                            column += 4 - (column % 4)
                        }
                        index = rest.index(after: index)
                    }
                }
            }
        }
    }

    return ListMarkerMatch(
        indent: indent,
        contentColumn: column,
        orderedStart: orderedStart,
        orderedDelimiter: orderedDelimiter,
        checked: checked,
        remainder: String(rest[index...])
    )
}

private func containsUnescapedPipe(_ line: String) -> Bool {
    var escaped = false
    var inCode = false
    var codeLength = 0
    var index = line.startIndex
    while index < line.endIndex {
        let character = line[index]
        if character == "`", !escaped {
            var length = 0
            var cursor = index
            while cursor < line.endIndex, line[cursor] == "`" {
                length += 1
                cursor = line.index(after: cursor)
            }
            if !inCode {
                inCode = true
                codeLength = length
            } else if length == codeLength {
                inCode = false
                codeLength = 0
            }
            index = cursor
            escaped = false
            continue
        }
        if escaped {
            escaped = false
            index = line.index(after: index)
            continue
        }
        if character == "\\" {
            escaped = true
            index = line.index(after: index)
            continue
        }
        if character == "|", !inCode { return true }
        index = line.index(after: index)
    }
    return false
}

private func tableCells(_ line: String) -> [String] {
    var cells: [String] = []
    var current = ""
    var escaped = false
    var inCode = false
    var codeLength = 0
    var index = line.startIndex
    while index < line.endIndex {
        let character = line[index]
        if character == "`", !escaped {
            var length = 0
            var cursor = index
            while cursor < line.endIndex, line[cursor] == "`" {
                length += 1
                cursor = line.index(after: cursor)
            }
            if !inCode {
                inCode = true
                codeLength = length
            } else if length == codeLength {
                inCode = false
            }
            current.append(contentsOf: line[index..<cursor])
            index = cursor
            continue
        }
        if escaped {
            current.append(character)
            escaped = false
            index = line.index(after: index)
            continue
        }
        if character == "\\" {
            current.append(character)
            escaped = true
            index = line.index(after: index)
            continue
        }
        if character == "|", !inCode {
            cells.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
            index = line.index(after: index)
            continue
        }
        current.append(character)
        index = line.index(after: index)
    }
    cells.append(current.trimmingCharacters(in: .whitespaces))
    if cells.first?.isEmpty == true {
        cells.removeFirst()
    }
    if cells.last?.isEmpty == true {
        cells.removeLast()
    }
    return cells
}

private func tableDelimiter(_ line: String) -> [MarkdownTableAlignment]? {
    var index = line.startIndex
    var alignments: [MarkdownTableAlignment] = []
    var sawPipe = false
    func skipSpace() {
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
    }
    skipSpace()
    if index < line.endIndex, line[index] == "|" {
        sawPipe = true
        index = line.index(after: index)
    }
    while index < line.endIndex {
        skipSpace()
        guard index < line.endIndex else { break }
        var left = false
        var right = false
        if line[index] == ":" {
            left = true
            index = line.index(after: index)
        }
        var dashes = 0
        while index < line.endIndex, line[index] == "-" {
            dashes += 1
            index = line.index(after: index)
        }
        if dashes == 0 { return nil }
        if index < line.endIndex, line[index] == ":" {
            right = true
            index = line.index(after: index)
        }
        if left && right {
            alignments.append(.center)
        } else if left {
            alignments.append(.left)
        } else if right {
            alignments.append(.right)
        } else {
            alignments.append(.none)
        }
        skipSpace()
        if index < line.endIndex, line[index] == "|" {
            sawPipe = true
            index = line.index(after: index)
            continue
        }
        break
    }
    skipSpace()
    guard sawPipe, !alignments.isEmpty, index == line.endIndex else { return nil }
    return alignments
}

private struct ParsedReferenceDefinition {
    var label: String
    var destination: String
    var title: String?
}

private func parseReferenceDefinition(_ line: String) -> ParsedReferenceDefinition? {
    let indent = leadingColumnCount(line)
    if indent > 3 { return nil }
    var content = stripColumns(line, indent)
    guard content.first == "[" else { return nil }
    content.removeFirst()
    guard let closing = unescapedDelimiter(in: content, matching: "]") else { return nil }
    let rawLabel = String(content[..<closing])
    guard acceptableReferenceLabel(rawLabel) else { return nil }
    content = String(content[content.index(after: closing)...])
    guard content.first == ":" else { return nil }
    content.removeFirst()
    content = trimHorizontalSpace(content)
    guard !content.isEmpty else { return nil }

    var destination = ""
    if content.first == "<" {
        content.removeFirst()
        guard let end = unescapedDelimiter(in: content, matching: ">") else { return nil }
        let wrapped = String(content[..<end])
        if wrapped.contains("<") || wrapped.contains("\n") { return nil }
        destination = unescapeMarkdown(wrapped)
        content = String(content[content.index(after: end)...])
    } else {
        var depth = 0
        var value = ""
        var index = content.startIndex
        while index < content.endIndex {
            let character = content[index]
            if character == "\\" {
                let next = content.index(after: index)
                guard next < content.endIndex else { return nil }
                value.append(content[next])
                index = content.index(after: next)
                continue
            }
            if character == " " || character == "\t" { break }
            if character == "(" {
                depth += 1
            } else if character == ")" {
                if depth == 0 { break }
                depth -= 1
            }
            value.append(character)
            index = content.index(after: index)
        }
        guard !value.isEmpty, depth == 0 else { return nil }
        destination = value
        content = String(content[index...])
    }

    content = trimHorizontalSpace(content)
    var title: String?
    if let marker = content.first, marker == "\"" || marker == "'" || marker == "(" {
        let closingMarker: Character = marker == "(" ? ")" : marker
        content.removeFirst()
        guard let end = unescapedDelimiter(in: content, matching: closingMarker) else { return nil }
        title = unescapeMarkdown(String(content[..<end]))
        content = String(content[content.index(after: end)...])
        content = trimHorizontalSpace(content)
    }
    guard content.isEmpty else { return nil }
    return ParsedReferenceDefinition(label: rawLabel, destination: destination, title: title)
}

private func acceptableReferenceLabel(_ label: String) -> Bool {
    guard label.count <= 999, !normalizeReferenceLabel(label).isEmpty else { return false }
    var escaped = false
    for character in label {
        if escaped {
            escaped = false
            continue
        }
        if character == "\\" {
            escaped = true
            continue
        }
        if character == "[" || character == "]" { return false }
    }
    return true
}

private func unescapedDelimiter(in text: String, matching target: Character) -> String.Index? {
    var escaped = false
    var index = text.startIndex
    while index < text.endIndex {
        let character = text[index]
        if escaped {
            escaped = false
            index = text.index(after: index)
            continue
        }
        if character == "\\" {
            escaped = true
            index = text.index(after: index)
            continue
        }
        if character == target { return index }
        index = text.index(after: index)
    }
    return nil
}

private func trimHorizontalSpace(_ text: String) -> String {
    var result = text
    while result.first == " " || result.first == "\t" { result.removeFirst() }
    while result.last == " " || result.last == "\t" { result.removeLast() }
    return result
}

private func unescapeMarkdown(_ text: String) -> String {
    var result = ""
    var escaped = false
    for character in text {
        if escaped {
            result.append(character)
            escaped = false
            continue
        }
        if character == "\\" {
            escaped = true
            continue
        }
        result.append(character)
    }
    if escaped { result.append("\\") }
    return result
}

private func resolveReferences(in blocks: [MarkdownBlock], definitions: ReferenceDefinitionMap) -> [MarkdownBlock] {
    blocks.map { resolveBlock($0, definitions: definitions) }
}

private func resolveBlock(_ block: MarkdownBlock, definitions: ReferenceDefinitionMap) -> MarkdownBlock {
    switch block {
    case .heading(let level, let inlines):
        return .heading(level: level, inlines: resolveInlines(inlines, definitions: definitions))
    case .paragraph(let inlines): return .paragraph(inlines: resolveInlines(inlines, definitions: definitions))
    case .codeBlock: return block
    case .blockQuote(let children):
        return .blockQuote(children: resolveReferences(in: children, definitions: definitions))
    case .list(let orderedStart, let tight, let items):
        let resolved = items.map { item in
            MarkdownListItem(
                checked: item.checked,
                children: resolveReferences(in: item.children, definitions: definitions)
            )
        }
        return .list(orderedStart: orderedStart, tight: tight, items: resolved)
    case .table(let alignments, let header, let rows):
        let resolvedHeader = header.map { MarkdownTableCell(inlines: resolveInlines($0.inlines, definitions: definitions)) }
        let resolvedRows = rows.map { row in
            row.map { MarkdownTableCell(inlines: resolveInlines($0.inlines, definitions: definitions)) }
        }
        return .table(alignments: alignments, header: resolvedHeader, rows: resolvedRows)
    case .thematicBreak: return block
    }
}

private func resolveInlines(_ inlines: [MarkdownInline], definitions: ReferenceDefinitionMap) -> [MarkdownInline] {
    inlines.flatMap { resolveInline($0, definitions: definitions) }
}

private func resolveInline(_ inline: MarkdownInline, definitions: ReferenceDefinitionMap) -> [MarkdownInline] {
    switch inline {
    case .unresolvedReference(let match):
        let children = resolveInlines(match.children, definitions: definitions)
        for (index, label) in match.labels.enumerated() where definitions.values[label] != nil {
            let defined = definitions.values[label]!
            let trailing = index < match.trailingAfterMatch.count ? match.trailingAfterMatch[index] : ""
            let linked: MarkdownInline
            if match.isImage {
                linked = .image(destination: defined.destination, alternativeText: plainText(children))
            } else {
                linked = .link(destination: defined.destination, title: defined.title, children: children)
            }
            if trailing.isEmpty { return [linked] }
            return [linked, .text(trailing)]
        }
        return [.text(match.opening)] + children + [.text(match.closing)]
    case .emphasis(let children): return [.emphasis(children: resolveInlines(children, definitions: definitions))]
    case .strong(let children): return [.strong(children: resolveInlines(children, definitions: definitions))]
    case .link(let destination, let title, let children):
        return [.link(destination: destination, title: title, children: resolveInlines(children, definitions: definitions))]
    case .text, .softBreak, .hardBreak, .code, .image: return [inline]
    }
}

private enum InlinePiece {
    case text(String)
    case softBreak
    case hardBreak
    case code(String)
    case image(destination: String, alternativeText: String)
    case link(destination: String, title: String?, children: [MarkdownInline])
    case unresolvedReference(UnresolvedReference)
    case emphasis([InlinePiece])
    case strong([InlinePiece])
    case delimiter(marker: Character, count: Int, canOpen: Bool, canClose: Bool)
}

private struct InlineParser {
    var text: String

    func parse(allowLinks: Bool) -> [MarkdownInline] {
        finalize(matchEmphasis(tokenize(allowLinks: allowLinks)))
    }

    func tokenize(allowLinks: Bool) -> [InlinePiece] {
        var pieces: [InlinePiece] = []
        var buffer = ""
        var index = text.startIndex
        func flush() {
            if !buffer.isEmpty {
                pieces.append(.text(buffer))
                buffer = ""
            }
        }
        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex {
                    let following = text[next]
                    if following == "\n" {
                        flush()
                        pieces.append(.hardBreak)
                        index = text.index(after: next)
                        continue
                    }
                    if isASCIIPunctuation(following) {
                        buffer.append(following)
                        index = text.index(after: next)
                        continue
                    }
                }
                buffer.append("\\")
                index = next < text.endIndex ? next : text.endIndex
                continue
            }
            if character == "`" {
                if let (code, next) = codeSpan(from: index) {
                    flush()
                    pieces.append(.code(code))
                    index = next
                    continue
                }
                while index < text.endIndex, text[index] == "`" {
                    buffer.append("`")
                    index = text.index(after: index)
                }
                continue
            }
            if character == "\n" {
                var spaces = 0
                while buffer.last == " " {
                    buffer.removeLast()
                    spaces += 1
                }
                if spaces < 2 {
                    buffer.append(String(repeating: " ", count: spaces))
                    flush()
                    pieces.append(.softBreak)
                } else {
                    flush()
                    pieces.append(.hardBreak)
                }
                index = text.index(after: index)
                continue
            }
            if character == "!" || character == "[" {
                if let parsed = link(from: index, allowLinks: allowLinks) {
                    flush()
                    pieces.append(parsed.piece)
                    index = parsed.next
                    continue
                }
            }
            if character == "<", let autolink = autolink(from: index) {
                flush()
                pieces.append(autolink.piece)
                index = autolink.next
                continue
            }
            if let bare = bareURL(from: index) {
                flush()
                pieces.append(bare.piece)
                index = bare.next
                continue
            }
            if character == "*" || character == "_" {
                var length = 0
                var cursor = index
                while cursor < text.endIndex, text[cursor] == character {
                    length += 1
                    cursor = text.index(after: cursor)
                }
                let before = index == text.startIndex ? nil : text[text.index(before: index)]
                let after = cursor < text.endIndex ? text[cursor] : nil
                let (canOpen, canClose) = flanking(marker: character, before: before, after: after)
                if canOpen || canClose {
                    flush()
                    pieces.append(.delimiter(marker: character, count: length, canOpen: canOpen, canClose: canClose))
                } else {
                    buffer.append(String(repeating: character, count: length))
                }
                index = cursor
                continue
            }
            buffer.append(character)
            index = text.index(after: index)
        }
        flush()
        return pieces
    }

    func codeSpan(from start: String.Index) -> (String, String.Index)? {
        var index = start
        var opener = 0
        while index < text.endIndex, text[index] == "`" {
            opener += 1
            index = text.index(after: index)
        }
        let contentStart = index
        while index < text.endIndex {
            if text[index] != "`" {
                index = text.index(after: index)
                continue
            }
            let closerStart = index
            var closer = 0
            while index < text.endIndex, text[index] == "`" {
                closer += 1
                index = text.index(after: index)
            }
            if closer == opener {
                var content = String(text[contentStart..<closerStart])
                content = content.replacingOccurrences(of: "\n", with: " ")
                if content.count >= 2, content.first == " ", content.last == " ", content.contains(where: { $0 != " " }) {
                    content.removeFirst()
                    content.removeLast()
                }
                return (content, index)
            }
        }
        return nil
    }

    func link(from start: String.Index, allowLinks: Bool) -> (piece: InlinePiece, next: String.Index)? {
        var index = start
        var image = false
        if text[index] == "!" {
            let next = text.index(after: index)
            guard next < text.endIndex, text[next] == "[" else { return nil }
            image = true
            index = next
        }
        guard index < text.endIndex, text[index] == "[" else { return nil }
        guard allowLinks || image else { return nil }
        let labelStart = text.index(after: index)
        guard let labelEnd = closingBracket(from: labelStart) else { return nil }
        let afterLabel = text.index(after: labelEnd)
        if afterLabel >= text.endIndex || text[afterLabel] != "(" {
            return reference(from: labelStart, labelEnd: labelEnd, image: image)
        }
        guard let destination = destination(from: text.index(after: afterLabel)) else { return nil }
        let label = String(text[labelStart..<labelEnd])
        if image {
            let alternative = plainText(InlineParser(text: label).parse(allowLinks: false))
            return (.image(destination: destination.value, alternativeText: alternative), destination.end)
        }
        let children = InlineParser(text: label).parse(allowLinks: false)
        return (.link(destination: destination.value, title: destination.title, children: children), destination.end)
    }

    func reference(from labelStart: String.Index, labelEnd: String.Index, image: Bool) -> (piece: InlinePiece, next: String.Index)? {
        let rawLabel = String(text[labelStart..<labelEnd])
        guard acceptableReferenceLabel(rawLabel) else { return nil }
        let shortcut = normalizeReferenceLabel(rawLabel)
        let afterLabel = text.index(after: labelEnd)
        let opening = image ? "![" : "["
        let children = InlineParser(text: rawLabel).parse(allowLinks: false)

        if afterLabel < text.endIndex, text[afterLabel] == "[" {
            let secondStart = text.index(after: afterLabel)
            if secondStart < text.endIndex, text[secondStart] == "]" {
                let end = text.index(after: secondStart)
                let match = UnresolvedReference(
                    labels: [shortcut],
                    trailingAfterMatch: [""],
                    children: children,
                    isImage: image,
                    opening: opening,
                    closing: "][]"
                )
                return (.unresolvedReference(match), end)
            }
            if let secondEnd = closingBracket(from: secondStart) {
                let referenceRaw = String(text[secondStart..<secondEnd])
                if acceptableReferenceLabel(referenceRaw) {
                    let end = text.index(after: secondEnd)
                    let secondLiteral = String(text[afterLabel..<end])
                    let match = UnresolvedReference(
                        labels: [normalizeReferenceLabel(referenceRaw), shortcut],
                        trailingAfterMatch: ["", secondLiteral],
                        children: children,
                        isImage: image,
                        opening: opening,
                        closing: "]" + secondLiteral
                    )
                    return (.unresolvedReference(match), end)
                }
            }
        }

        let match = UnresolvedReference(
            labels: [shortcut],
            trailingAfterMatch: [""],
            children: children,
            isImage: image,
            opening: opening,
            closing: "]"
        )
        return (.unresolvedReference(match), afterLabel)
    }

    func closingBracket(from start: String.Index) -> String.Index? {
        var depth = 1
        var index = start
        while index < text.endIndex {
            if text[index] == "\\" {
                let next = text.index(after: index)
                index = next < text.endIndex ? text.index(after: next) : text.endIndex
                continue
            }
            if text[index] == "[" {
                depth += 1
            } else if text[index] == "]" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    func destination(from start: String.Index) -> (value: String, title: String?, end: String.Index)? {
        var index = skipWhitespace(start)
        var value = ""
        if index < text.endIndex, text[index] == "<" {
            index = text.index(after: index)
            while index < text.endIndex, text[index] != ">", text[index] != "\n" {
                if text[index] == "\\" {
                    let next = text.index(after: index)
                    if next < text.endIndex {
                        value.append(text[next])
                        index = text.index(after: next)
                        continue
                    }
                }
                value.append(text[index])
                index = text.index(after: index)
            }
            guard index < text.endIndex, text[index] == ">" else { return nil }
            index = text.index(after: index)
        } else {
            var depth = 0
            while index < text.endIndex {
                let character = text[index]
                if character == "\\" {
                    let next = text.index(after: index)
                    if next < text.endIndex {
                        value.append(text[next])
                        index = text.index(after: next)
                        continue
                    }
                }
                if character == " " || character == "\n" || character == "\t" { break }
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    if depth == 0 { break }
                    depth -= 1
                }
                value.append(character)
                index = text.index(after: index)
            }
        }
        index = skipWhitespace(index)
        var title: String?
        if index < text.endIndex, text[index] == "\"" || text[index] == "'" {
            let quote = text[index]
            index = text.index(after: index)
            var titleValue = ""
            while index < text.endIndex, text[index] != quote, text[index] != "\n" {
                if text[index] == "\\" {
                    let next = text.index(after: index)
                    if next < text.endIndex {
                        titleValue.append(text[next])
                        index = text.index(after: next)
                        continue
                    }
                }
                titleValue.append(text[index])
                index = text.index(after: index)
            }
            guard index < text.endIndex, text[index] == quote else { return nil }
            index = text.index(after: index)
            title = titleValue
            index = skipWhitespace(index)
        }
        guard index < text.endIndex, text[index] == ")" else { return nil }
        return (value, title, text.index(after: index))
    }

    func skipWhitespace(_ start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex, text[index] == " " || text[index] == "\t" || text[index] == "\n" {
            index = text.index(after: index)
        }
        return index
    }

    func autolink(from start: String.Index) -> (piece: InlinePiece, next: String.Index)? {
        var index = text.index(after: start)
        let contentStart = index
        while index < text.endIndex, text[index] != ">", text[index] != " ", text[index] != "\n" {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == ">", index > contentStart else { return nil }
        let content = String(text[contentStart..<index])
        let next = text.index(after: index)
        if isEmailAddress(content) {
            let destination = content.lowercased().hasPrefix("mailto:") ? content : "mailto:\(content)"
            return (.link(destination: destination, title: nil, children: [.text(content)]), next)
        }
        if isAutolinkURL(content) {
            return (.link(destination: content, title: nil, children: [.text(content)]), next)
        }
        return nil
    }

    func bareURL(from start: String.Index) -> (piece: InlinePiece, next: String.Index)? {
        let rest = text[start...]
        guard rest.hasPrefix("https://") || rest.hasPrefix("http://") else { return nil }
        if start > text.startIndex {
            let previous = text[text.index(before: start)]
            if flankingClass(previous) == .word { return nil }
        }
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace || character == "<" { break }
            index = text.index(after: index)
        }
        while index > start {
            let previous = text[text.index(before: index)]
            if ".,;:!?".contains(previous) {
                index = text.index(before: index)
                continue
            }
            break
        }
        let url = String(text[start..<index])
        guard url.count > "https://".count else { return nil }
        return (.link(destination: url, title: nil, children: [.text(url)]), index)
    }

    func matchEmphasis(_ input: [InlinePiece]) -> [InlinePiece] {
        var pieces = input
        var closerIndex = 0
        while closerIndex < pieces.count {
            guard case let .delimiter(marker, count, canOpen, canClose) = pieces[closerIndex], canClose, count > 0 else {
                closerIndex += 1
                continue
            }
            var openerIndex = closerIndex - 1
            var matched = false
            while openerIndex >= 0 {
                guard case let .delimiter(openMarker, openCount, openCanOpen, openCanClose) = pieces[openerIndex],
                      openMarker == marker, openCanOpen, openCount > 0
                else {
                    openerIndex -= 1
                    continue
                }
                if !emphasisAllowed(
                    openCount: openCount,
                    openCanOpen: openCanOpen,
                    openCanClose: openCanClose,
                    closeCount: count,
                    closeCanOpen: canOpen,
                    closeCanClose: canClose
                ) {
                    openerIndex -= 1
                    continue
                }
                let used = (openCount >= 2 && count >= 2) ? 2 : 1
                let interior = Array(pieces[(openerIndex + 1)..<closerIndex])
                let children = matchEmphasis(interior)
                let wrapped: InlinePiece = used == 2 ? .strong(children) : .emphasis(children)
                let remainingOpen = openCount - used
                let remainingClose = count - used
                var replacement: [InlinePiece] = []
                if remainingOpen > 0 {
                    replacement.append(.delimiter(marker: marker, count: remainingOpen, canOpen: openCanOpen, canClose: openCanClose))
                }
                replacement.append(wrapped)
                if remainingClose > 0 {
                    replacement.append(.delimiter(marker: marker, count: remainingClose, canOpen: canOpen, canClose: canClose))
                }
                pieces.replaceSubrange(openerIndex...closerIndex, with: replacement)
                closerIndex = openerIndex + replacement.count - (remainingClose > 0 ? 1 : 0)
                matched = true
                break
            }
            if !matched {
                closerIndex += 1
            }
        }
        return pieces.map { piece in
            if case let .delimiter(marker, count, _, _) = piece {
                return .text(String(repeating: marker, count: count))
            }
            return piece
        }
    }

    func finalize(_ pieces: [InlinePiece]) -> [MarkdownInline] {
        pieces.map { piece in
            switch piece {
            case .text(let text): return .text(text)
            case .softBreak: return .softBreak
            case .hardBreak: return .hardBreak
            case .code(let code): return .code(code)
            case .image(let destination, let alternativeText):
                return .image(destination: destination, alternativeText: alternativeText)
            case .link(let destination, let title, let children):
                return .link(destination: destination, title: title, children: children)
            case .unresolvedReference(let match): return .unresolvedReference(match)
            case .emphasis(let children): return .emphasis(children: finalize(children))
            case .strong(let children): return .strong(children: finalize(children))
            case .delimiter(let marker, let count, _, _): return .text(String(repeating: marker, count: count))
            }
        }
    }
}

private func plainText(_ inlines: [MarkdownInline]) -> String {
    inlines.map { inline in
        switch inline {
        case .text(let text): return text
        case .softBreak, .hardBreak: return " "
        case .code(let code): return code
        case .emphasis(let children), .strong(let children): return plainText(children)
        case .link(_, _, let children): return plainText(children)
        case .image(_, let alternativeText): return alternativeText
        case .unresolvedReference(let match): return match.opening + plainText(match.children) + match.closing
        }
    }.joined()
}

private func emphasisAllowed(
    openCount: Int,
    openCanOpen: Bool,
    openCanClose: Bool,
    closeCount: Int,
    closeCanOpen: Bool,
    closeCanClose: Bool
) -> Bool {
    let openerAmbiguous = openCanOpen && openCanClose
    let closerAmbiguous = closeCanOpen && closeCanClose
    if openerAmbiguous || closerAmbiguous {
        let sum = openCount + closeCount
        if sum.isMultiple(of: 3), !openCount.isMultiple(of: 3) || !closeCount.isMultiple(of: 3) {
            return false
        }
    }
    return true
}

private enum FlankingClass {
    case whitespace
    case punctuation
    case word
}

private func flanking(marker: Character, before: Character?, after: Character?) -> (Bool, Bool) {
    let beforeClass = flankingClass(before)
    let afterClass = flankingClass(after)
    let left = afterClass != .whitespace && !(afterClass == .punctuation && beforeClass == .word)
    let right = beforeClass != .whitespace && !(beforeClass == .punctuation && afterClass == .word)
    if marker == "_" {
        let canOpen = left && (!right || beforeClass == .punctuation)
        let canClose = right && (!left || afterClass == .punctuation)
        return (canOpen, canClose)
    }
    return (left, right)
}

private func flankingClass(_ character: Character?) -> FlankingClass {
    guard let character else { return .whitespace }
    if character == " " || character == "\t" || character == "\n" || character == "\r" {
        return .whitespace
    }
    if isASCIIPunctuation(character) {
        return .punctuation
    }
    return .word
}

private func isASCIIPunctuation(_ character: Character) -> Bool {
    guard let value = character.asciiValue else { return false }
    return (value >= 33 && value <= 47) || (value >= 58 && value <= 64) || (value >= 91 && value <= 96) || (value >= 123 && value <= 126)
}

private func isEmailAddress(_ text: String) -> Bool {
    guard let at = text.firstIndex(of: "@"), at != text.startIndex else { return false }
    let domainStart = text.index(after: at)
    guard domainStart < text.endIndex else { return false }
    if text[..<at].contains(":") { return false }
    let domain = text[domainStart...]
    return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
}

private func isAutolinkURL(_ text: String) -> Bool {
    guard let colon = text.firstIndex(of: ":"), colon != text.startIndex else { return false }
    let scheme = text[..<colon]
    guard scheme.count <= 32, let first = scheme.first, isASCIILetter(first) else { return false }
    for character in scheme {
        if isASCIILetter(character) || character.isNumber || character == "+" || character == "-" || character == "." {
            continue
        }
        return false
    }
    return text.index(after: colon) < text.endIndex
}

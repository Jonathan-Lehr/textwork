import Markdown
import TextworkEditor

/// Maps Apple's swift-markdown tree onto the same span model as the editor highlighter.
///
/// This target is a benchmark and correctness comparison. The app does not link it.
public struct SwiftMarkdownHighlighter: Sendable {
    public init() {}

    public func highlight(_ text: String) -> [HighlightSpan] {
        let document = Document(parsing: text)
        var walker = Walker(text: text)
        walker.visit(document)
        return walker.spans.sorted(by: spanPrecedes)
    }
}

private struct Walker: MarkupWalker {
    let text: String
    let lines: LineIndex
    var spans: [HighlightSpan] = []
    var roleStack: [HighlightRole] = []

    init(text: String) {
        self.text = text
        self.lines = LineIndex(text)
    }

    mutating func visitHeading(_ heading: Heading) {
        let role = HighlightRole.heading(level: heading.level)
        roleStack.append(role)
        recordSyntaxGaps(of: heading, role: role)
        descendInto(heading)
        _ = roleStack.popLast()
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        roleStack.append(.emphasis)
        recordSyntaxGaps(of: emphasis, role: .emphasis)
        descendInto(emphasis)
        _ = roleStack.popLast()
    }

    mutating func visitStrong(_ strong: Strong) {
        roleStack.append(.strong)
        recordSyntaxGaps(of: strong, role: .strong)
        descendInto(strong)
        _ = roleStack.popLast()
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let sourceRange = inlineCode.range, let outer = lines.utf16Range(sourceRange, in: text) else { return }
        recordLeaf(outer: outer, literal: inlineCode.code, role: .codeSpan)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let sourceRange = codeBlock.range, let outer = lines.utf16Range(sourceRange, in: text) else { return }
        recordLeaf(outer: outer, literal: codeBlock.code, role: .codeBlock)
    }

    mutating func visitLink(_ link: Link) {
        roleStack.append(.link)
        recordSyntaxGaps(of: link, role: .link)
        descendInto(link)
        _ = roleStack.popLast()
    }

    mutating func visitImage(_ image: Image) {
        roleStack.append(.image)
        recordSyntaxGaps(of: image, role: .image)
        descendInto(image)
        _ = roleStack.popLast()
    }

    mutating func visitListItem(_ listItem: ListItem) {
        recordSyntaxGaps(of: listItem, role: .listMarker)
        descendInto(listItem)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        recordSyntaxGaps(of: blockQuote, role: .blockQuote)
        descendInto(blockQuote)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let sourceRange = thematicBreak.range, let outer = lines.utf16Range(sourceRange, in: text) else { return }
        append(outer, role: .thematicBreak, isSyntax: true)
    }

    mutating func visitTable(_ table: Table) {
        descendInto(table)
    }

    mutating func visitTableHead(_ head: Table.Head) {
        descendInto(head)
    }

    mutating func visitTableBody(_ body: Table.Body) {
        descendInto(body)
    }

    mutating func visitTableRow(_ row: Table.Row) {
        recordSyntaxGaps(of: row, role: .table)
        descendInto(row)
    }

    mutating func visitTableCell(_ cell: Table.Cell) {
        roleStack.append(.table)
        descendInto(cell)
        _ = roleStack.popLast()
    }

    mutating func visitText(_ textNode: Text) {
        guard let role = roleStack.last, let sourceRange = textNode.range, let range = lines.utf16Range(sourceRange, in: text) else {
            return
        }
        append(range, role: role, isSyntax: false)
    }

    private mutating func recordSyntaxGaps(of markup: Markup, role: HighlightRole) {
        guard let parent = markup.range, let parentRange = lines.utf16Range(parent, in: text) else { return }
        var cursor = parentRange.lowerBound
        for child in markup.children {
            guard let childRange = child.range, let converted = lines.utf16Range(childRange, in: text) else { continue }
            if converted.lowerBound > cursor {
                append(cursor..<converted.lowerBound, role: role, isSyntax: true)
            }
            cursor = max(cursor, converted.upperBound)
        }
        if cursor < parentRange.upperBound {
            append(cursor..<parentRange.upperBound, role: role, isSyntax: true)
        }
    }

    private mutating func recordLeaf(outer: Range<Int>, literal: String, role: HighlightRole) {
        let outerText = substring(outer)
        guard let match = outerText.range(of: literal) else {
            append(outer, role: role, isSyntax: false)
            return
        }
        let matchStart = outer.lowerBound + outerText.utf16.distance(from: outerText.startIndex, to: match.lowerBound)
        let matchEnd = matchStart + literal.utf16.count
        if matchStart > outer.lowerBound {
            append(outer.lowerBound..<matchStart, role: role, isSyntax: true)
        }
        if matchEnd > matchStart {
            append(matchStart..<matchEnd, role: role, isSyntax: false)
        }
        if matchEnd < outer.upperBound {
            append(matchEnd..<outer.upperBound, role: role, isSyntax: true)
        }
    }

    private mutating func append(_ range: Range<Int>, role: HighlightRole, isSyntax: Bool) {
        guard range.upperBound > range.lowerBound else { return }
        spans.append(HighlightSpan(startUTF16: range.lowerBound, endUTF16: range.upperBound, role: role, isSyntax: isSyntax))
    }

    private func substring(_ range: Range<Int>) -> String {
        guard range.lowerBound >= 0, range.upperBound <= text.utf16.count else { return "" }
        let start = String.Index(utf16Offset: range.lowerBound, in: text)
        let end = String.Index(utf16Offset: range.upperBound, in: text)
        return String(text[start..<end])
    }
}

private struct LineIndex {
    let text: String
    var lineStarts: [String.Index]
    var utf16Starts: [Int]

    init(_ text: String) {
        self.text = text
        var lineStarts = [text.startIndex]
        var utf16Starts = [0]
        var utf16Count = 0
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\n" {
                utf16Count += 1
                index = text.index(after: index)
                lineStarts.append(index)
                utf16Starts.append(utf16Count)
                continue
            }
            if character == "\r" {
                utf16Count += 1
                let next = text.index(after: index)
                index = next
                if next < text.endIndex && text[next] == "\n" {
                    utf16Count += 1
                    index = text.index(after: next)
                }
                lineStarts.append(index)
                utf16Starts.append(utf16Count)
                continue
            }
            utf16Count += character.utf16.count
            index = text.index(after: index)
        }
        self.lineStarts = lineStarts
        self.utf16Starts = utf16Starts
    }

    func utf16Range(_ range: SourceRange, in text: String) -> Range<Int>? {
        let start = utf16Offset(line: range.lowerBound.line, column: range.lowerBound.column)
        let end = utf16Offset(line: range.upperBound.line, column: range.upperBound.column)
        guard end >= start else { return nil }
        return start..<end
    }

    func utf16Offset(line: Int, column: Int) -> Int {
        guard line >= 1 else { return 0 }
        if line > lineStarts.count {
            return utf16Starts.last ?? 0
        }
        let lineUTF16 = utf16Starts[line - 1]
        let lineStart = lineStarts[line - 1]
        let byteBudget = max(0, column - 1)
        var index = lineStart
        var consumedBytes = 0
        var extraUTF16 = 0
        while consumedBytes < byteBudget && index < text.endIndex {
            let character = text[index]
            let byteCount = character.utf8.count
            if consumedBytes + byteCount > byteBudget { break }
            consumedBytes += byteCount
            extraUTF16 += character.utf16.count
            index = text.index(after: index)
        }
        return lineUTF16 + extraUTF16
    }
}

private func spanPrecedes(_ lhs: HighlightSpan, _ rhs: HighlightSpan) -> Bool {
    if lhs.startUTF16 != rhs.startUTF16 { return lhs.startUTF16 < rhs.startUTF16 }
    if lhs.endUTF16 != rhs.endUTF16 { return lhs.endUTF16 < rhs.endUTF16 }
    if lhs.isSyntax != rhs.isSyntax { return lhs.isSyntax && !rhs.isSyntax }
    return lhs.role.rawValue < rhs.role.rawValue
}

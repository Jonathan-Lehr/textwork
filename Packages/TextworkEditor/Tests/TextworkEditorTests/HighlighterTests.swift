import XCTest
@testable import TextworkEditor

final class HighlighterTests: XCTestCase {
    private let highlighter = MarkdownHighlighter()

    func testHashHeadings() {
        XCTAssertEqual(content("# Title", role: .heading1), ["Title"])
        XCTAssertEqual(syntax("# Title", role: .heading1), ["#", " "])
        XCTAssertEqual(content("## Second", role: .heading2), ["Second"])
        XCTAssertEqual(content("###### Sixth", role: .heading6), ["Sixth"])
        XCTAssertEqual(content("# Title #", role: .heading1), ["Title"])
    }

    func testUnderlineHeadings() {
        XCTAssertEqual(content("Title\n=====", role: .heading1), ["Title"])
        XCTAssertEqual(syntax("Title\n=====", role: .heading1), ["====="])
        XCTAssertEqual(content("Subtitle\n---", role: .heading2), ["Subtitle"])
    }

    func testEmphasisAndStrong() {
        XCTAssertEqual(content("a *em* b", role: .emphasis), ["em"])
        XCTAssertEqual(syntax("a *em* b", role: .emphasis), ["*", "*"])
        XCTAssertEqual(content("a **bold** b", role: .strong), ["bold"])
        XCTAssertEqual(content("a _em_ b", role: .emphasis), ["em"])
        XCTAssertEqual(content("a __bold__ b", role: .strong), ["bold"])
        XCTAssertTrue(content("a_b_c", role: .emphasis).isEmpty)
        XCTAssertTrue(content(#"a \*not\* b"#, role: .emphasis).isEmpty)

        let nested = "***both***"
        XCTAssertTrue(content(nested, role: .strong).contains("both"))
        XCTAssertTrue(content(nested, role: .emphasis).contains { $0.contains("both") })
    }

    func testCodeSpansAndFences() {
        XCTAssertEqual(content("use `code` here", role: .codeSpan), ["code"])
        XCTAssertEqual(syntax("use `code` here", role: .codeSpan), ["`", "`"])

        let fenced = "```swift\nlet answer = 42\n```"
        XCTAssertEqual(content(fenced, role: .codeBlock), ["let answer = 42"])
        XCTAssertTrue(syntax(fenced, role: .codeBlock).contains("```swift"))
        XCTAssertTrue(content(fenced, role: .emphasis).isEmpty)

        let emphasisInsideFence = "```\n*not emphasis*\n```"
        XCTAssertTrue(content(emphasisInsideFence, role: .emphasis).isEmpty)
        XCTAssertEqual(content(emphasisInsideFence, role: .codeBlock), ["*not emphasis*"])
    }

    func testLinksAndImages() {
        XCTAssertEqual(content("[Example](https://example.com)", role: .link), ["Example"])
        XCTAssertTrue(syntax("[Example](https://example.com)", role: .link).joined().contains("https://example.com"))
        XCTAssertEqual(content("![Alt](images/figure.png)", role: .image), ["Alt"])
        XCTAssertTrue(syntax("![Alt](images/figure.png)", role: .image).joined().contains("images/figure.png"))
        XCTAssertEqual(content("see <https://example.com> now", role: .link), ["https://example.com"])
        XCTAssertEqual(content("see https://example.com now", role: .link), ["https://example.com"])
    }

    func testListsQuotesAndThematicBreaks() {
        XCTAssertEqual(syntax("- item", role: .listMarker), ["- "])
        XCTAssertEqual(syntax("1. item", role: .listMarker), ["1. "])
        XCTAssertEqual(syntax("- [ ] item", role: .listMarker), ["- [ ] "])
        XCTAssertEqual(syntax("- [x] item", role: .listMarker), ["- [x] "])
        XCTAssertEqual(syntax("> quoted", role: .blockQuote), ["> "])
        XCTAssertEqual(syntax("---", role: .thematicBreak), ["---"])
        XCTAssertEqual(syntax("* * *", role: .thematicBreak), ["* * *"])
    }

    func testTables() {
        let table = """
        | a | b |
        | --- | --- |
        | 1 | 2 |
        """
        XCTAssertEqual(content(table, role: .table), ["a", "b", "1", "2"])
        let markers = syntax(table, role: .table).joined()
        XCTAssertTrue(markers.contains("|"))
        XCTAssertTrue(markers.contains("---"))
    }

    func testQuoteCanContainAHeading() {
        XCTAssertEqual(content("> # Title", role: .heading1), ["Title"])
        XCTAssertEqual(syntax("> # Title", role: .blockQuote), ["> "])
    }

    func testMultibyteOffsets() {
        XCTAssertEqual(content("# 👋 Hello", role: .heading1), ["👋 Hello"])
        XCTAssertEqual(content("# Hi\r\n", role: .heading1), ["Hi"])
    }

    func testSpansStayInsideTheBuffer() {
        let text = sampleDocument
        let snapshot = highlighter.highlight(text)
        let limit = text.utf16.count
        for span in snapshot.spans {
            XCTAssertGreaterThanOrEqual(span.startUTF16, 0)
            XCTAssertLessThanOrEqual(span.endUTF16, limit)
            XCTAssertLessThan(span.startUTF16, span.endUTF16)
        }
    }

    func testIncrementalEditMatchesFullHighlight() {
        var text = String(repeating: sampleDocument, count: 12)
        var snapshot = highlighter.highlight(text)
        let edits = ["Z", "\n\n## Inserted\n", "x", "`code`"]
        for replacement in edits {
            let midpoint = text.utf16.count / 2
            let edit = MarkdownEdit(range: midpoint..<midpoint, replacement: replacement)
            text = applying(edit, to: text)
            snapshot = highlighter.apply(edit, to: snapshot)
            let fresh = highlighter.highlight(text)
            XCTAssertEqual(snapshot.spans, fresh.spans)
            XCTAssertGreaterThan(snapshot.statistics.blocksReused, 0)
        }
    }

    func testMiddleInsertReusesMostBlocks() {
        let text = String(repeating: sampleDocument, count: 30)
        let snapshot = highlighter.highlight(text)
        let midpoint = text.utf16.count / 2
        let updated = highlighter.apply(MarkdownEdit(range: midpoint..<midpoint, replacement: "Z"), to: snapshot)
        XCTAssertLessThan(updated.statistics.blocksReparsed, updated.statistics.blockCount / 2)
        XCTAssertGreaterThan(updated.statistics.blocksReused, updated.statistics.blocksReparsed)
    }

    private func content(_ text: String, role: HighlightRole) -> [String] {
        pieces(text, role: role, syntax: false)
    }

    private func syntax(_ text: String, role: HighlightRole) -> [String] {
        pieces(text, role: role, syntax: true)
    }

    private func pieces(_ text: String, role: HighlightRole, syntax: Bool) -> [String] {
        highlighter.highlight(text).spans.filter { $0.role == role && $0.isSyntax == syntax }.map { slice(text, $0) }
    }

    private func slice(_ text: String, _ span: HighlightSpan) -> String {
        let start = String.Index(utf16Offset: span.startUTF16, in: text)
        let end = String.Index(utf16Offset: span.endUTF16, in: text)
        return String(text[start..<end])
    }

    private func applying(_ edit: MarkdownEdit, to text: String) -> String {
        var updated = text
        let start = String.Index(utf16Offset: edit.range.lowerBound, in: updated)
        let end = String.Index(utf16Offset: edit.range.upperBound, in: updated)
        updated.replaceSubrange(start..<end, with: edit.replacement)
        return updated
    }
}

private let sampleDocument = """
# Heading

A paragraph with *emphasis*, **strong**, and `code` plus a [link](https://example.com).

> A quoted line.

- item one
- item two

| a | b |
| --- | --- |
| 1 | 2 |

```swift
let answer = 42
```

![Alt](images/figure.png)

"""

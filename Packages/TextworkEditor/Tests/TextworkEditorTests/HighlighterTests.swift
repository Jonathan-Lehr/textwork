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

    func testReferenceLinksAndDefinitions() {
        let source = """
        [example]: https://example.com "Title"
        [Café]: https://example.com/caf%C3%A9

        [Example]

        [text][example]

        [Example][]

        ![Alt][example]

        [Café]
        """
        XCTAssertEqual(
            content(source, role: .link),
            ["example", "https://example.com", "Title", "Café", "https://example.com/caf%C3%A9", "Example", "text", "Example", "Café"]
        )
        XCTAssertEqual(content(source, role: .image), ["Alt"])
        let syntax = syntax(source, role: .link).joined()
        XCTAssertTrue(syntax.contains("][example]"))
        XCTAssertTrue(syntax.contains("][]"))
        XCTAssertTrue(syntax.contains("\""))

        XCTAssertTrue(content("[Example]", role: .link).isEmpty)
        XCTAssertTrue(content("[text][missing]", role: .link).isEmpty)
        XCTAssertEqual(content("[Still](https://example.com)", role: .link), ["Still"])

        let folded = "[Foo   Bar]: /url\n\n[foo bar]"
        XCTAssertEqual(content(folded, role: .link), ["Foo   Bar", "/url", "foo bar"])
    }

    func testReferenceDefinitionParserReadsLabelDestinationAndTitle() throws {
        func parse(_ source: String) -> ReferenceDefinitionParse? {
            let bytes = Array(source.utf8)
            let lines = DocumentBuffer.lines(in: bytes)
            return ReferenceDefinitionParser.parseLine(bytes: bytes, line: lines[0])
        }
        func slice(_ source: String, _ range: Range<Int>) -> String {
            String(decoding: Array(source.utf8)[range], as: UTF8.self)
        }
        func html(_ source: String) -> ParsedReferenceDefinition? {
            parseReferenceDefinition(source)
        }

        let angle = "[example]: <https://example.com>"
        let parsedAngle = try XCTUnwrap(parse(angle))
        XCTAssertEqual(parsedAngle.normalizedLabel, "example")
        XCTAssertEqual(slice(angle, parsedAngle.destination), "https://example.com")
        XCTAssertNotNil(parsedAngle.destinationOpening)
        XCTAssertNil(parsedAngle.title)
        XCTAssertEqual(html(angle)?.destination, "https://example.com")

        let empty = "[example]: <>"
        let parsedEmpty = try XCTUnwrap(parse(empty))
        XCTAssertTrue(parsedEmpty.destination.isEmpty)
        XCTAssertNotNil(parsedEmpty.destinationOpening)
        XCTAssertNotNil(parsedEmpty.destinationClosing)
        XCTAssertEqual(html(empty)?.destination, "")

        let parentheses = "[example]: http://example.com/a(b)"
        let parsedParentheses = try XCTUnwrap(parse(parentheses))
        XCTAssertEqual(slice(parentheses, parsedParentheses.destination), "http://example.com/a(b)")
        XCTAssertEqual(html(parentheses)?.destination, "http://example.com/a(b)")

        let doubleQuoted = "[example]: /url \"title\""
        let parsedDouble = try XCTUnwrap(parse(doubleQuoted))
        XCTAssertEqual(parsedDouble.title.map { slice(doubleQuoted, $0) }, "title")
        XCTAssertEqual(html(doubleQuoted)?.title, "title")

        let singleQuoted = "[example]: /url 'title'"
        let parsedSingle = try XCTUnwrap(parse(singleQuoted))
        XCTAssertEqual(parsedSingle.title.map { slice(singleQuoted, $0) }, "title")
        XCTAssertEqual(html(singleQuoted)?.title, "title")

        let escaped = "[example]: /url \"a\\\"b\""
        let parsedEscaped = try XCTUnwrap(parse(escaped))
        XCTAssertEqual(parsedEscaped.title.map { slice(escaped, $0) }, "a\\\"b")
        XCTAssertEqual(html(escaped)?.title, "a\"b")

        let tabbed = "[example]:\t/url\t\"Title\""
        let parsedTabbed = try XCTUnwrap(parse(tabbed))
        XCTAssertEqual(slice(tabbed, parsedTabbed.destination), "/url")
        XCTAssertEqual(parsedTabbed.title.map { slice(tabbed, $0) }, "Title")
        XCTAssertEqual(html(tabbed)?.title, "Title")

        let spaced = "[example]:  /url  \"Title\""
        XCTAssertEqual(parse(spaced)?.title.map { slice(spaced, $0) }, "Title")
        XCTAssertEqual(html(spaced)?.title, "Title")

        let quotedInsideDestination = "[example]: /url\"title\""
        let parsedQuotedDestination = try XCTUnwrap(parse(quotedInsideDestination))
        XCTAssertEqual(slice(quotedInsideDestination, parsedQuotedDestination.destination), "/url\"title\"")
        XCTAssertNil(parsedQuotedDestination.title)
        XCTAssertEqual(html(quotedInsideDestination)?.destination, "/url\"title\"")
        XCTAssertNil(html(quotedInsideDestination)?.title)
        XCTAssertNil(parse("[example]: </url>\"title\""))
        XCTAssertNil(html("[example]: </url>\"title\""))
        let spacedAfterAngle = "[example]: </url> \"title\""
        XCTAssertEqual(parse(spacedAfterAngle)?.title.map { slice(spacedAfterAngle, $0) }, "title")
        XCTAssertEqual(html(spacedAfterAngle)?.title, "title")
        XCTAssertNil(parse("[example] https://example.com"))
        XCTAssertNil(html("[example] https://example.com"))

        let trailingBackslash = "[example]: /url\\"
        let parsedBackslash = try XCTUnwrap(parse(trailingBackslash))
        XCTAssertEqual(slice(trailingBackslash, parsedBackslash.destination), "/url\\")
        XCTAssertNil(html(trailingBackslash))

        let control = "[example]: /url\u{01}"
        XCTAssertNil(parse(control))
        XCTAssertEqual(html(control)?.destination, "/url\u{01}")

        let exact = "[" + String(repeating: "a", count: MarkdownScanLimit.maximumReferenceLabelLength) + "]: /url"
        XCTAssertNotNil(parse(exact))
        XCTAssertNotNil(html(exact))
        let tooLong = "[" + String(repeating: "a", count: MarkdownScanLimit.maximumReferenceLabelLength + 1) + "]: /url"
        XCTAssertNil(parse(tooLong))
        XCTAssertNil(html(tooLong))
        let accents = "[" + String(repeating: "é", count: 500) + "]: /url"
        XCTAssertGreaterThan(Array(String(repeating: "é", count: 500).utf8).count, MarkdownScanLimit.maximumReferenceLabelLength)
        XCTAssertNotNil(parse(accents))
        XCTAssertNotNil(html(accents))

        XCTAssertNotNil(parse("   [example]: /url"))
        XCTAssertNotNil(html("   [example]: /url"))
        XCTAssertNil(parse("    [example]: /url"))
        XCTAssertNil(html("    [example]: /url"))
        XCTAssertNil(parse("\t[example]: /url"))
        XCTAssertNil(html("\t[example]: /url"))
    }

    func testTruncatedFourByteLeadCountsAsOneUTF16Unit() {
        let truncated: [UInt8] = [0xF0, 0x9F]
        let width = DocumentBuffer.scalarWidth(truncated, 0)
        XCTAssertEqual(width.0, truncated.count)
        XCTAssertEqual(width.1, 1)
        let complete: [UInt8] = [0xF0, 0x9F, 0x98, 0x80]
        let completeWidth = DocumentBuffer.scalarWidth(complete, 0)
        XCTAssertEqual(completeWidth.0, 4)
        XCTAssertEqual(completeWidth.1, 2)
    }

    func testInlineHTMLAndHTMLBlocks() {
        let inline = "Use <em>word</em> and <!-- note --> here."
        XCTAssertEqual(content(inline, role: .html), ["em", "em", " note "])
        XCTAssertEqual(syntax(inline, role: .html), ["<", ">", "</", ">", "<!--", "-->"])
        XCTAssertTrue(content(inline, role: .emphasis).isEmpty)

        let emphasized = "Use <em>*word*</em> here."
        XCTAssertEqual(content(emphasized, role: .emphasis), ["word"])
        XCTAssertEqual(content(emphasized, role: .html), ["em", "em"])
        XCTAssertEqual(content("see <https://example.com> now", role: .link), ["https://example.com"])
        XCTAssertTrue(content("see <https://example.com> now", role: .html).isEmpty)

        let block = "<div>\n*not emphasis*\n</div>\n"
        XCTAssertTrue(content(block, role: .emphasis).isEmpty)
        XCTAssertEqual(content(block, role: .html), ["div", "div"])
        XCTAssertTrue(syntax(block, role: .html).contains("<"))
        XCTAssertTrue(syntax(block, role: .html).contains("</"))

        let script = "<script>\n*not emphasis*\n</script>\n"
        XCTAssertTrue(content(script, role: .emphasis).isEmpty)
        XCTAssertTrue(content(script, role: .html).contains("script"))

        let comment = "<!--\nsecret\n-->\n"
        XCTAssertTrue(content(comment, role: .html).joined().contains("secret"))
        XCTAssertTrue(syntax(comment, role: .html).contains("<!--"))
        XCTAssertTrue(syntax(comment, role: .html).contains("-->"))
    }

    func testIncrementalReferenceAndHTMLMatchFullHighlight() {
        var text = """
        [example]: https://example.com

        See [example] and <em>tags</em>.

        <div>
        *inside*
        </div>

        Tail.
        """
        var snapshot = highlighter.highlight(text)
        let edits = ["Z", "\n\n## Inserted\n", " [example]", "<!-- note -->"]
        for replacement in edits {
            let midpoint = text.utf16.count / 2
            let edit = MarkdownEdit(range: midpoint..<midpoint, replacement: replacement)
            text = applying(edit, to: text)
            snapshot = highlighter.apply(edit, to: snapshot)
            XCTAssertEqual(snapshot.spans, highlighter.highlight(text).spans)
        }
    }

    func testDeletingAllTextKeepsInvalidatedRangesInsideTheDocument() {
        let text = "# Title\n\nBody with *emphasis*.\n"
        let snapshot = highlighter.highlight(text)
        let cleared = highlighter.apply(
            MarkdownEdit(range: 0..<text.utf16.count, replacement: ""),
            to: snapshot
        )
        XCTAssertEqual(cleared.utf16Count, 0)
        assertRangesInsideDocument(cleared.invalidatedUTF16Ranges, length: cleared.utf16Count)
        let typed = highlighter.apply(MarkdownEdit(range: 0..<0, replacement: "Hello"), to: cleared)
        XCTAssertEqual(typed.spans, highlighter.highlight("Hello").spans)
        assertRangesInsideDocument(typed.invalidatedUTF16Ranges, length: typed.utf16Count)
    }

    func testMiddleInsertInvalidatesAFractionOfTheDocument() {
        let text = String(repeating: sampleDocument, count: 20)
        let snapshot = highlighter.highlight(text)
        XCTAssertEqual(snapshot.invalidatedUTF16Ranges, [0..<text.utf16.count])
        let midpoint = text.utf16.count / 2
        let updated = highlighter.apply(MarkdownEdit(range: midpoint..<midpoint, replacement: "Z"), to: snapshot)
        let invalidated = updated.invalidatedUTF16Ranges.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(invalidated, 0)
        XCTAssertLessThan(invalidated, text.utf16.count / 10)
        let edited = applying(MarkdownEdit(range: midpoint..<midpoint, replacement: "Z"), to: text)
        XCTAssertEqual(updated.spans, highlighter.highlight(edited).spans)
    }

    func testAddingADefinitionInvalidatesTheReference() {
        let text = "See [example] please.\n\nTail paragraph.\n"
        let snapshot = highlighter.highlight(text)
        XCTAssertTrue(snapshot.spans.filter { $0.role == .link }.isEmpty)
        let insertion = "[example]: https://example.com\n\n"
        let edit = MarkdownEdit(range: 0..<0, replacement: insertion)
        let updated = highlighter.apply(edit, to: snapshot)
        let updatedText = insertion + text
        XCTAssertEqual(updated.spans, highlighter.highlight(updatedText).spans)
        XCTAssertTrue(content(updatedText, role: .link).contains("example"))
        XCTAssertTrue(content(updatedText, role: .link).contains("https://example.com"))
        let reference = updatedText.range(of: "See ")!
        let referenceUTF16 = updatedText.utf16.distance(from: updatedText.startIndex, to: reference.upperBound)
        XCTAssertTrue(updated.invalidatedUTF16Ranges.contains { $0.contains(referenceUTF16) })
        let tail = updatedText.range(of: "Tail")!
        let tailUTF16 = updatedText.utf16.distance(from: updatedText.startIndex, to: tail.lowerBound)
        XCTAssertFalse(updated.invalidatedUTF16Ranges.contains { $0.contains(tailUTF16) })
        let invalidated = updated.invalidatedUTF16Ranges.reduce(0) { $0 + $1.count }
        XCTAssertLessThan(invalidated, updatedText.utf16.count)
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

    private func assertRangesInsideDocument(_ ranges: [Range<Int>], length: Int) {
        for range in ranges {
            XCTAssertGreaterThanOrEqual(range.lowerBound, 0)
            XCTAssertLessThan(range.lowerBound, range.upperBound)
            XCTAssertLessThanOrEqual(range.upperBound, length)
        }
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

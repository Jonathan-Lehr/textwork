import XCTest
@testable import TextworkEditor

final class FencedCodeTests: XCTestCase {
    private let highlighter = MarkdownHighlighter()

    func testSwiftFenceColorsKeywordsStringsNumbersCommentsTypesAndAttributes() {
        let source = """
        ```swift
        import Foundation
        /// note
        let answer: Int = 42
        let text = "hello"
        @available(iOS 17, *)
        func greet(_ name: String) {}
        /*
        block
        */
        ```
        """
        XCTAssertEqual(pieces(source, role: .codeKeyword), ["import", "let", "let", "func"])
        XCTAssertEqual(pieces(source, role: .codeString), ["\"hello\""])
        XCTAssertTrue(pieces(source, role: .codeNumber).contains("42"))
        XCTAssertTrue(pieces(source, role: .codeComment).contains("/// note"))
        XCTAssertTrue(pieces(source, role: .codeComment).joined(separator: "\n").contains("block"))
        let types = pieces(source, role: .codeType)
        XCTAssertTrue(types.contains("Foundation"))
        XCTAssertTrue(types.contains("Int"))
        XCTAssertTrue(types.contains("String"))
        XCTAssertEqual(pieces(source, role: .codeAttribute), ["@available"])
        XCTAssertTrue(pieces(source, role: .codeBlock).contains("let answer: Int = 42"))
    }

    func testJSONShellAndHTMLFences() {
        let json = """
        ```json
        { "name": true, "count": 2 }
        ```
        """
        XCTAssertEqual(pieces(json, role: .codeString), ["\"name\"", "\"count\""])
        XCTAssertEqual(pieces(json, role: .codeKeyword), ["true"])
        XCTAssertEqual(pieces(json, role: .codeNumber), ["2"])

        let shell = """
        ```bash
        echo "hi" # note
        if true; then
        fi
        ```
        """
        XCTAssertEqual(pieces(shell, role: .codeString), ["\"hi\""])
        XCTAssertEqual(pieces(shell, role: .codeComment), ["# note"])
        XCTAssertEqual(pieces(shell, role: .codeKeyword), ["if", "then", "fi"])
        XCTAssertFalse(pieces(shell, role: .codeKeyword).contains("echo"))

        let zsh = "```zsh\nexport NAME=1\n```"
        XCTAssertEqual(pieces(zsh, role: .codeKeyword), ["export"])
        XCTAssertEqual(pieces("```sh\n# only\n```", role: .codeComment), ["# only"])

        let html = """
        ```html
        <div class="box">Hi</div>
        <!-- hidden -->
        ```
        """
        XCTAssertEqual(pieces(html, role: .codeTag), ["div", "div"])
        XCTAssertEqual(pieces(html, role: .codeAttribute), ["class"])
        XCTAssertEqual(pieces(html, role: .codeString), ["\"box\""])
        XCTAssertEqual(pieces(html, role: .codeComment), ["<!-- hidden -->"])
    }

    func testUnknownLanguagesKeepTheSingleCodeColor() {
        let source = """
        ```python
        let answer = 42
        ```
        """
        XCTAssertTrue(pieces(source, role: .codeKeyword).isEmpty)
        XCTAssertTrue(pieces(source, role: .codeString).isEmpty)
        XCTAssertTrue(pieces(source, role: .codeNumber).isEmpty)
        XCTAssertEqual(pieces(source, role: .codeBlock), ["let answer = 42"])
        XCTAssertNil(FencedCodeTokenizer.language(named: "python"))
        XCTAssertEqual(FencedCodeTokenizer.language(named: "BASH"), .shell)
    }

    func testEditingOutsideAFenceDoesNotRetokenizeIt() {
        let fence = "```swift\nlet answer = 42\n```\n"
        let text = String(repeating: "A paragraph of words.\n\n", count: 20) + fence + "Tail paragraph.\n"
        let snapshot = highlighter.highlight(text)
        let keywordBefore = pieces(in: snapshot, text: text, role: .codeKeyword)
        XCTAssertEqual(keywordBefore, ["let"])
        let tail = text.range(of: "Tail")!
        let start = text.utf16.distance(from: text.startIndex, to: tail.lowerBound)
        let edited = highlighter.apply(MarkdownEdit(range: start..<start, replacement: "Z"), to: snapshot)
        let editedText = applying(MarkdownEdit(range: start..<start, replacement: "Z"), to: text)
        XCTAssertEqual(edited.spans, highlighter.highlight(editedText).spans)
        XCTAssertEqual(pieces(in: edited, text: editedText, role: .codeKeyword), ["let"])
        XCTAssertLessThan(edited.statistics.blocksReparsed, 4)
        XCTAssertGreaterThan(edited.statistics.blocksReused, snapshot.statistics.blockCount / 2)
        let fenceSpans = snapshot.spans.filter { $0.role == .codeKeyword || $0.role == .codeNumber }
        let editedFence = edited.spans.filter { $0.role == .codeKeyword || $0.role == .codeNumber }
        XCTAssertEqual(fenceSpans, editedFence)
    }

    func testEditingInsideAFenceRetokenizesOnlyThatBlock() {
        let prefix = String(repeating: "A paragraph of words.\n\n", count: 20)
        let text = prefix + "```swift\nlet answer = 42\n```\n"
        let snapshot = highlighter.highlight(text)
        let number = text.range(of: "42")!
        let start = text.utf16.distance(from: text.startIndex, to: number.lowerBound)
        let edit = MarkdownEdit(range: start..<(start + 2), replacement: "7")
        let updated = highlighter.apply(edit, to: snapshot)
        let updatedText = applying(edit, to: text)
        XCTAssertEqual(updated.spans, highlighter.highlight(updatedText).spans)
        XCTAssertEqual(pieces(in: updated, text: updatedText, role: .codeKeyword), ["let"])
        XCTAssertEqual(pieces(in: updated, text: updatedText, role: .codeNumber), ["7"])
        XCTAssertLessThan(updated.statistics.blocksReparsed, 4)
        XCTAssertGreaterThan(updated.statistics.blocksReused, 10)
    }

    func testPreviewUsesTheSameTokenizer() {
        let renderer = MarkdownHTMLRenderer()
        let swift = renderer.renderBody("```swift\nlet answer = 42\n```")
        XCTAssertTrue(swift.contains("<span class=\"code-keyword\">let</span>"))
        XCTAssertTrue(swift.contains("<span class=\"code-number\">42</span>"))
        XCTAssertTrue(swift.contains("class=\"language-swift\""))
        let python = renderer.renderBody("```python\nlet answer = 42\n```")
        XCTAssertFalse(python.contains("code-keyword"))
        XCTAssertTrue(python.contains("let answer = 42"))
        let html = renderer.renderBody("```html\n<div class=\"x\">\n```")
        XCTAssertTrue(html.contains("<span class=\"code-tag\">div</span>"))
        XCTAssertTrue(html.contains("&quot;") || html.contains("class=\"code-string\""))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(".code-keyword { color: var(--code-keyword); }"))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(HighlightTheme.standard.color(for: .codeKeyword, isSyntax: false).light.cssHex))
    }

    private func pieces(_ text: String, role: HighlightRole) -> [String] {
        pieces(in: highlighter.highlight(text), text: text, role: role)
    }

    private func pieces(in snapshot: HighlightSnapshot, text: String, role: HighlightRole) -> [String] {
        snapshot.spans.filter { $0.role == role && !$0.isSyntax }.map { slice(text, $0) }
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

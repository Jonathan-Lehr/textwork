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
        XCTAssertFalse(types.contains("Int"))
        XCTAssertFalse(types.contains("String"))
        let systemTypes = pieces(source, role: .codeSystemType)
        XCTAssertTrue(systemTypes.contains("Int"))
        XCTAssertTrue(systemTypes.contains("String"))
        XCTAssertEqual(pieces(source, role: .codeAttribute), ["@available"])
        XCTAssertTrue(pieces(source, role: .codeBlock).contains("let answer: Int = 42"))
        XCTAssertTrue(pieces(source, role: .codeMember).isEmpty)
    }

    func testSwiftPropertiesAndMethodsUseTheMemberColor() {
        let source = """
        ```swift
        let storage = textView.textStorage
        storage.length
        textView?.textStorage
        panel . isVisible
        applyTypingAttributes()
        refresh ()
        highlighter.highlight(source)
        let value = NSAttributedString(string: "Code")
        func greet(_ name: String) {}
        func
        declared()
        if ready { return }
        let count = 42
        ```
        """
        XCTAssertEqual(
            pieces(source, role: .codeMember),
            [
                "textStorage",
                "length",
                "textStorage",
                "isVisible",
                "applyTypingAttributes",
                "refresh",
                "highlight",
            ]
        )
        XCTAssertTrue(pieces(source, role: .codeSystemType).contains("NSAttributedString"))
        XCTAssertTrue(pieces(source, role: .codeSystemType).contains("String"))
        XCTAssertFalse(pieces(source, role: .codeType).contains("NSAttributedString"))
        XCTAssertFalse(pieces(source, role: .codeMember).contains("NSAttributedString"))
        XCTAssertFalse(pieces(source, role: .codeMember).contains("greet"))
        XCTAssertFalse(pieces(source, role: .codeMember).contains("declared"))
        XCTAssertFalse(pieces(source, role: .codeMember).contains("string"))
        XCTAssertFalse(pieces(source, role: .codeMember).contains("name"))
        XCTAssertFalse(pieces(source, role: .codeMember).contains("ready"))
        XCTAssertFalse(pieces(source, role: .codeMember).contains("count"))
        XCTAssertTrue(pieces(source, role: .codeKeyword).contains("func"))
        XCTAssertTrue(pieces(source, role: .codeKeyword).contains("if"))
        XCTAssertTrue(pieces(source, role: .codeKeyword).contains("return"))
        XCTAssertEqual(pieces(source, role: .codeNumber), ["42"])
        XCTAssertTrue(pieces("```bash\necho(1)\n```", role: .codeMember).isEmpty)
    }

    func testSwiftBindingsAndSystemTypes() {
        let source = """
        ```swift
        @Binding var text: String
        @MainActor @State var configuration: EditorConfiguration
        let highlighter = MarkdownHighlighter()
        let count = text.count
        guard let name = text else { return }
        print(name)
        if let value = name {
            value
        }
        name
        struct Sample {
            var stored: Int
            func read() { stored }
        }
        let outside = NSView()
        UIView.self
        ```
        """
        XCTAssertEqual(
            pieces(source, role: .codeAttribute),
            ["@Binding", "@MainActor", "@State"]
        )
        XCTAssertEqual(
            pieces(source, role: .codeVariable),
            [
                "text", "configuration", "highlighter", "count", "text", "name", "text",
                "name", "value", "name", "value", "stored", "stored", "outside",
            ]
        )
        XCTAssertTrue(pieces(source, role: .codeSystemType).contains("String"))
        XCTAssertTrue(pieces(source, role: .codeSystemType).contains("Int"))
        XCTAssertTrue(pieces(source, role: .codeSystemType).contains("NSView"))
        XCTAssertTrue(pieces(source, role: .codeSystemType).contains("UIView"))
        XCTAssertTrue(pieces(source, role: .codeType).contains("EditorConfiguration"))
        XCTAssertTrue(pieces(source, role: .codeType).contains("MarkdownHighlighter"))
        XCTAssertTrue(pieces(source, role: .codeType).contains("Sample"))
        XCTAssertFalse(pieces(source, role: .codeType).contains("String"))
        XCTAssertFalse(pieces(source, role: .codeVariable).contains("read"))
        XCTAssertTrue(pieces(source, role: .codeKeyword).contains("let"))
        XCTAssertTrue(pieces(source, role: .codeKeyword).contains("var"))
        XCTAssertTrue(pieces(source, role: .codeKeyword).contains("guard"))
        XCTAssertTrue(pieces(source, role: .codeMember).contains("count"))
        XCTAssertTrue(pieces(source, role: .codeMember).contains("print"))
        XCTAssertFalse(pieces(source, role: .codeVariable).contains("print"))
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
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(".code-keyword { color: var(--code-keyword); font-weight: bold; }"))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(HighlightTheme.standard.color(for: .codeKeyword, isSyntax: false).light.cssHex))
        let members = renderer.renderBody("```swift\nstorage.length\napplyTypingAttributes()\nfunc greet() {}\n```")
        XCTAssertTrue(members.contains("<span class=\"code-member\">length</span>"))
        XCTAssertTrue(members.contains("<span class=\"code-member\">applyTypingAttributes</span>"))
        XCTAssertFalse(members.contains("<span class=\"code-member\">greet</span>"))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(".code-member { color: var(--code-member); }"))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(HighlightTheme.standard.color(for: .codeMember, isSyntax: false).light.cssHex))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(HighlightTheme.standard.color(for: .codeMember, isSyntax: false).dark.cssHex))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(".code-variable { color: var(--code-variable); }"))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(".code-system-type { color: var(--code-system-type); }"))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(HighlightTheme.standard.color(for: .codeSystemType, isSyntax: false).light.cssHex))
        XCTAssertTrue(MarkdownHTMLRenderer.stylesheet.contains(HighlightTheme.standard.color(for: .codeAttribute, isSyntax: false).dark.cssHex))
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

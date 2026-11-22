import Foundation
import XCTest
import TextworkEditor
import TextworkHighlightOracle

final class OracleTests: XCTestCase {
    func testSwiftMarkdownAgreesOnCoreContent() {
        let cases: [(String, HighlightRole, String)] = [
            ("# Title", .heading1, "Title"),
            ("## Second", .heading2, "Second"),
            ("Title\n=====", .heading1, "Title"),
            ("a *em* b", .emphasis, "em"),
            ("a **bold** b", .strong, "bold"),
            ("use `code` here", .codeSpan, "code"),
            ("```\nlet answer = 42\n```", .codeBlock, "let answer = 42"),
            ("[Example](https://example.com)", .link, "Example"),
            ("![Alt](images/figure.png)", .image, "Alt"),
            ("> quoted", .blockQuote, ">"),
            ("---", .thematicBreak, "---"),
            ("| a | b |\n| --- | --- |\n| 1 | 2 |", .table, "a"),
        ]
        let oracle = SwiftMarkdownHighlighter()
        for (source, role, expected) in cases {
            let pieces = oracle.highlight(source)
                .filter { $0.role == role && !$0.isSyntax }
                .map { slice(source, $0) }
            let syntax = oracle.highlight(source)
                .filter { $0.role == role && $0.isSyntax }
                .map { slice(source, $0) }
            let haystack = (pieces + syntax).joined(separator: "\n")
            XCTAssertTrue(
                haystack.contains(expected),
                "swift-markdown missed \(expected) for \(role) in \(source.debugDescription). content=\(pieces) syntax=\(syntax)"
            )
        }
    }

    func testAttributedStringConsumesMarkdownSyntax() throws {
        #if os(macOS) || os(iOS)
        let source = "This is *emphasized* and **strong**."
        let options = AttributedString.MarkdownParsingOptions(appliesSourcePositionAttributes: true)
        let parsed = try AttributedString(markdown: source, options: options)
        let rendered = String(parsed.characters)
        XCTAssertFalse(rendered.contains("*"))
        XCTAssertTrue(rendered.contains("emphasized"))
        XCTAssertTrue(rendered.contains("strong"))
        var sawSourcePosition = false
        for run in parsed.runs where run.markdownSourcePosition != nil {
            sawSourcePosition = true
        }
        XCTAssertTrue(sawSourcePosition)
        #else
        throw XCTSkip("AttributedString Markdown parsing is an Apple-platform API")
        #endif
    }

    private func slice(_ text: String, _ span: HighlightSpan) -> String {
        let start = String.Index(utf16Offset: span.startUTF16, in: text)
        let end = String.Index(utf16Offset: span.endUTF16, in: text)
        return String(text[start..<end])
    }
}

import XCTest
@testable import TextworkEditor

final class MarkdownHTMLTests: XCTestCase {
    private let renderer = MarkdownHTMLRenderer()

    func testHeadingsParagraphsAndBreaks() {
        XCTAssertEqual(body("# Textwork"), "<h1>Textwork</h1>")
        XCTAssertEqual(body("## Second"), "<h2>Second</h2>")
        XCTAssertEqual(body("Title\n====="), "<h1>Title</h1>")
        XCTAssertEqual(body("Subtitle\n---"), "<h2>Subtitle</h2>")
        XCTAssertEqual(body("One.\n\nTwo."), "<p>One.</p>\n<p>Two.</p>")
        XCTAssertEqual(body("One.\r\n\r\nTwo."), "<p>One.</p>\n<p>Two.</p>")
        XCTAssertEqual(body("---"), "<hr>")
        XCTAssertEqual(body("hello\nworld"), "<p>hello\nworld</p>")
        XCTAssertEqual(body("hello  \nworld"), "<p>hello<br>world</p>")
        XCTAssertEqual(body("hello\\\nworld"), "<p>hello<br>world</p>")
    }

    func testInlineStylesCodeAndEscapes() {
        XCTAssertEqual(body("a *em* b"), "<p>a <em>em</em> b</p>")
        XCTAssertEqual(body("a **bold** b"), "<p>a <strong>bold</strong> b</p>")
        XCTAssertEqual(body("a _em_ b"), "<p>a <em>em</em> b</p>")
        XCTAssertEqual(body("a __bold__ b"), "<p>a <strong>bold</strong> b</p>")
        XCTAssertEqual(body("a_b_c"), "<p>a_b_c</p>")
        XCTAssertEqual(body(#"a \*not\* b"#), "<p>a *not* b</p>")
        XCTAssertEqual(body("***both***"), "<p><em><strong>both</strong></em></p>")
        XCTAssertEqual(body("use `code` here"), "<p>use <code>code</code> here</p>")
        XCTAssertEqual(body("`*em*`"), "<p><code>*em*</code></p>")
        XCTAssertEqual(body("`` `code` ``"), "<p><code>`code`</code></p>")
        XCTAssertEqual(body("a &amp; b"), "<p>a &amp; b</p>")
        XCTAssertEqual(body("a < b"), "<p>a &lt; b</p>")
        XCTAssertEqual(body("Hello <script>alert(1)</script>"), "<p>Hello &lt;script&gt;alert(1)&lt;/script&gt;</p>")
        XCTAssertEqual(body("<div>hi</div>"), "<p>&lt;div&gt;hi&lt;/div&gt;</p>")
    }

    func testLinksImagesAndUnsafeDestinations() {
        XCTAssertEqual(
            body("[Example](https://example.com)"),
            "<p><a href=\"https://example.com\">Example</a></p>"
        )
        XCTAssertEqual(
            body("[Example](https://example.com \"Title\")"),
            "<p><a href=\"https://example.com\" title=\"Title\">Example</a></p>"
        )
        XCTAssertEqual(
            body("see <https://example.com> now"),
            "<p>see <a href=\"https://example.com\">https://example.com</a> now</p>"
        )
        XCTAssertEqual(
            body("see https://example.com now"),
            "<p>see <a href=\"https://example.com\">https://example.com</a> now</p>"
        )
        XCTAssertEqual(body("[click](javascript:alert(1))"), "<p>click</p>")
        XCTAssertEqual(body("[click](JavaScript:alert(1))"), "<p>click</p>")
        XCTAssertFalse(body("[click](javascript:alert(1))").lowercased().contains("javascript:"))
        XCTAssertEqual(body("![Alt](images/figure.png)"), "<p><img src=\"images/figure.png\" alt=\"Alt\"></p>")
        XCTAssertEqual(body("![a](javascript:alert(1))"), "<p>a</p>")

        let preview = MarkdownHTMLRenderer(imageAddressing: .preview)
        XCTAssertEqual(
            preview.renderBody("![Alt](images/figure.png)"),
            "<p><img src=\"textwork-preview://document/images/figure.png\" alt=\"Alt\"></p>"
        )
        XCTAssertEqual(
            preview.renderBody("![Alt](https://example.com/a.png)"),
            "<p><img src=\"https://example.com/a.png\" alt=\"Alt\"></p>"
        )
        XCTAssertTrue(preview.renderBody("![Alt](<my figure.png>)").contains("my%20figure.png"))
    }

    func testReferenceLinksResolveAndDefinitionsStayOutOfTheBody() {
        XCTAssertEqual(
            body("[example]: https://example.com\n\n[Example]"),
            "<p><a href=\"https://example.com\">Example</a></p>"
        )
        XCTAssertEqual(
            body("[example]: https://example.com \"Title\"\n\n[text][example]"),
            "<p><a href=\"https://example.com\" title=\"Title\">text</a></p>"
        )
        XCTAssertEqual(
            body("[example]: https://example.com\n\n[Example][]"),
            "<p><a href=\"https://example.com\">Example</a></p>"
        )
        XCTAssertEqual(
            body("[Example]\n\n[example]: https://example.com"),
            "<p><a href=\"https://example.com\">Example</a></p>"
        )
        XCTAssertEqual(body("[Example]"), "<p>[Example]</p>")
        XCTAssertEqual(body("[example]: https://example.com"), "")
        XCTAssertEqual(
            body("[foo bar]: /url\n\n[Foo   Bar]"),
            "<p><a href=\"/url\">Foo   Bar</a></p>"
        )
        XCTAssertEqual(
            body("[id]: /url\n\n[*em*][id]"),
            "<p><a href=\"/url\"><em>em</em></a></p>"
        )
        XCTAssertEqual(
            body("[fig]: images/figure.png\n\n![Alt][fig]"),
            "<p><img src=\"images/figure.png\" alt=\"Alt\"></p>"
        )
        XCTAssertEqual(body("[click]: javascript:alert(1)\n\n[click]"), "<p>click</p>")
        XCTAssertFalse(body("[click]: javascript:alert(1)\n\n[click]").lowercased().contains("javascript:"))
        XCTAssertEqual(
            body("[missing]: https://example.com\n\n[text][other]\n\n[missing]"),
            "<p>[text][other]</p>\n<p><a href=\"https://example.com\">missing</a></p>"
        )
    }

    func testListsQuotesTablesAndCode() {
        XCTAssertEqual(body("- item"), "<ul>\n<li>item</li>\n</ul>")
        XCTAssertEqual(body("- a\n- b"), "<ul>\n<li>a</li>\n<li>b</li>\n</ul>")
        XCTAssertEqual(body("- a\n\n- b"), "<ul>\n<li><p>a</p></li>\n<li><p>b</p></li>\n</ul>")
        XCTAssertEqual(body("- a\n  - b"), "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul></li>\n</ul>")
        XCTAssertEqual(body("1. item"), "<ol>\n<li>item</li>\n</ol>")
        XCTAssertEqual(body("1) item"), "<ol>\n<li>item</li>\n</ol>")
        XCTAssertEqual(body("2. two\n3. three"), "<ol start=\"2\">\n<li>two</li>\n<li>three</li>\n</ol>")
        XCTAssertEqual(
            body("- [ ] one\n- [x] two\n- [X] three"),
            """
            <ul>
            <li class="task"><input type="checkbox" disabled> one</li>
            <li class="task"><input type="checkbox" disabled checked> two</li>
            <li class="task"><input type="checkbox" disabled checked> three</li>
            </ul>
            """
        )
        XCTAssertEqual(body("> quoted"), "<blockquote>\n<p>quoted</p>\n</blockquote>")
        XCTAssertEqual(
            body("> > inner"),
            "<blockquote>\n<blockquote>\n<p>inner</p>\n</blockquote>\n</blockquote>"
        )
        XCTAssertEqual(
            body("| a | b |\n| :--- | ---: |\n| 1 | 2 |"),
            """
            <table>
            <thead>
            <tr><th style="text-align: left">a</th><th style="text-align: right">b</th></tr>
            </thead>
            <tbody>
            <tr><td style="text-align: left">1</td><td style="text-align: right">2</td></tr>
            </tbody>
            </table>
            """
        )
        XCTAssertEqual(
            body("```swift\nlet answer = 42\n```"),
            "<pre><code class=\"language-swift\"><span class=\"code-keyword\">let</span> answer = <span class=\"code-number\">42</span>\n</code></pre>"
        )
        XCTAssertEqual(body("```\n*not emphasis*\n```"), "<pre><code>*not emphasis*\n</code></pre>")
        XCTAssertEqual(body("~~~\ncode\n~~~"), "<pre><code>code\n</code></pre>")
        XCTAssertEqual(body("    indented"), "<pre><code>indented\n</code></pre>")
    }

    func testWelcomeSampleKeepsBlockStructure() {
        let expected = [
            "<h1>Textwork</h1>",
            "<p>A plain-text Markdown editor. The card on the side is a read-only preview.</p>",
            "<p>Write with <em>emphasis</em>, <strong>strong</strong>, and <code>inline code</code>.</p>",
            """
            <ul>
            <li>Lists keep their markers</li>
            <li><a href="https://example.com">Links</a> stay in the source</li>
            <li>Images use a path relative to the file: <img src="images/figure.png" alt="Alt"></li>
            </ul>
            """,
            """
            <blockquote>
            <p>Block quotes are still just text.</p>
            </blockquote>
            """,
            """
            <table>
            <thead>
            <tr><th>Syntax</th><th>Shown</th></tr>
            </thead>
            <tbody>
            <tr><td>raw</td><td>live</td></tr>
            </tbody>
            </table>
            """,
            "<pre><code class=\"language-swift\"><span class=\"code-keyword\">let</span> answer = <span class=\"code-number\">42</span>\n</code></pre>",
        ].joined(separator: "\n")
        XCTAssertEqual(body(welcomeSample), expected)
    }

    func testDocumentStylesheetFollowsAppearanceAndRefusesScripts() {
        let document = renderer.renderDocument("# Title\n\n## Section\n\n<script>alert(1)</script>")
        XCTAssertTrue(document.contains("<h1>Title</h1>"))
        XCTAssertTrue(document.contains("<h2>Section</h2>"))
        XCTAssertTrue(document.contains("color-scheme: light dark"))
        XCTAssertTrue(document.contains("@media (prefers-color-scheme: dark)"))
        XCTAssertTrue(document.contains("h1 { font-size: 2rem;"))
        XCTAssertTrue(document.contains("width: min(78.2ch, 100%)"))
        XCTAssertTrue(document.contains("font: 15px/1.55 -apple-system"))
        XCTAssertTrue(document.contains("color: var(--text)"))
        XCTAssertTrue(document.contains("background: var(--code-fill)"))
        XCTAssertTrue(document.contains("font-size: calc(12.9px + 1pt)"))
        XCTAssertTrue(document.contains("line-height: calc(18.705px - 3pt)"))
        XCTAssertTrue(document.contains("margin-inline: auto"))
        XCTAssertTrue(document.contains("h2 { font-size: 1.55rem;"))
        XCTAssertTrue(document.contains("script-src 'none'"))
        XCTAssertFalse(document.contains("<script"))
        XCTAssertTrue(document.contains("&lt;script&gt;"))
        XCTAssertTrue(document.contains(MarkdownHTMLRenderer.stylesheet))
        XCTAssertTrue(document.contains("background: canvas"))
        XCTAssertFalse(document.contains("--page:"))
    }

    func testPreviewPathsStayInsideTheDocumentDirectory() {
        let root = URL(fileURLWithPath: "/Users/example/Notes", isDirectory: true).standardizedFileURL
        let image = MarkdownHTMLRenderer.fileURL(forPreviewPath: "images/figure.png", in: root)
        XCTAssertEqual(
            image?.path,
            root.appendingPathComponent("images").appendingPathComponent("figure.png").standardizedFileURL.path
        )
        XCTAssertEqual(
            MarkdownHTMLRenderer.fileURL(forPreviewPath: "/images/figure.png", in: root)?.path,
            image?.path
        )
        XCTAssertNil(MarkdownHTMLRenderer.fileURL(forPreviewPath: "../Secrets/key", in: root))
        XCTAssertNil(MarkdownHTMLRenderer.fileURL(forPreviewPath: "images/../../Secrets/key", in: root))
        XCTAssertNil(MarkdownHTMLRenderer.fileURL(forPreviewPath: "..", in: root))
    }

    private func body(_ markdown: String) -> String {
        renderer.renderBody(markdown)
    }

    private var welcomeSample: String {
        """
        # Textwork

        A plain-text Markdown editor. The card on the side is a read-only preview.

        Write with *emphasis*, **strong**, and `inline code`.

        - Lists keep their markers
        - [Links](https://example.com) stay in the source
        - Images use a path relative to the file: ![Alt](images/figure.png)

        > Block quotes are still just text.

        | Syntax | Shown |
        | --- | --- |
        | raw | live |

        ```swift
        let answer = 42
        ```
        """
    }
}

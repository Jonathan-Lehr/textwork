# ADR 0005: HTML preview from our own renderer

- Status: Accepted
- Date: 2026-11-22

## Context

The read-only preview used `AttributedString(markdown:)`. That API keeps inline styles and drops block structure, so paragraphs, lists, quotes, tables, and heading sizes run together. HTML export and a later PDF export through the system print path need the same rendered document.

`swift-markdown` already parses CommonMark and GitHub-flavored Markdown for the highlighter oracle. Linking it from the app would ship cmark in the product. [ADR 0004](0004-syntax-highlighting.md) keeps that package off the app target. The preview does not need the oracle's source ranges. It needs a document tree and escaped HTML.

[ADR 0002](0002-native-swiftui.md) said the app would not add a web view. That was about the editor. SwiftUI `Text` cannot show this document, and the preview must stay visually distinct from the text view.

## Decision

`TextworkEditor` renders Markdown to HTML with a hand-rolled parser. The app preview and HTML export both call `MarkdownHTMLRenderer`. The grammar covers CommonMark blocks and inlines used by the editor, plus GitHub-flavored tables, fenced code, and task lists. Raw HTML is escaped. `javascript:`, `data:`, and `file:` destinations are not written into links or images.

The preview is a `WKWebView` inside the existing inset card. It is not editable. Relative images are loaded through a `textwork-preview` URL scheme limited to the document's directory. Link clicks are cancelled and opened with the system (`NSWorkspace` or `UIApplication`). The page is replaced as the user types, after a short debounce, by setting the article's HTML and restoring the scroll offset. That update is the reason JavaScript is enabled: macOS `WKWebView` has no public scroll view, and loading the document again flashes and jumps. The document's content security policy is `script-src 'none'`, so the page cannot run a script of its own.

## Consequences

The preview shows headings, paragraphs, lists, quotes, tables, and code as separate blocks, and export can use the same HTML. The renderer is not a full CommonMark implementation. Reference-style links, strikethrough, and footnotes stay as text. Raw HTML is shown as text on purpose. Character references cover a small named set plus numeric references. Some list and delimiter edge cases will differ from cmark.

PDF export is still the system print path. It should print this HTML rather than grow a second renderer. A sandboxed build will need security-scoped access to the document directory for images next to the file; the preview already starts that access when the system gives it.

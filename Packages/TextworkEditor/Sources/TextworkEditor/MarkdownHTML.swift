import Foundation

/// How image destinations are written into HTML.
///
/// HTML export leaves the path the author wrote. The preview rewrites a
/// relative path onto the preview URL scheme so the web view can read the
/// file without taking a broader file-system privilege.
public enum MarkdownImageAddressing: Sendable, Equatable {
    case authored
    case preview
}

/// Renders Markdown to HTML for the preview and for HTML export.
///
/// One pipeline covers both. The grammar is CommonMark plus GitHub-flavored
/// tables, fenced code, and task lists. Reference-style links resolve against
/// `[label]: destination` definitions anywhere in the document. Raw HTML is
/// escaped instead of being inserted, so a document cannot add a script or an
/// event handler. Character references cover the names this renderer emits
/// (`amp`, `lt`, `gt`, `quot`, `apos`, `nbsp`) and numeric references.
public struct MarkdownHTMLRenderer: Sendable {
    public static let previewScheme = "textwork-preview"
    public static let previewHost = "document"

    public var imageAddressing: MarkdownImageAddressing

    public init(imageAddressing: MarkdownImageAddressing = .authored) {
        self.imageAddressing = imageAddressing
    }

    /// The default stylesheet. The preview and HTML export both embed it.
    ///
    /// Role colors come from ``HighlightTheme/standard``. Light values sit on
    /// `:root`. Dark values replace them under `prefers-color-scheme: dark`.
    /// Inline code keeps a light gray chip. Fenced and indented code do not.
    /// Emphasis and strong inherit the body color. Margins and the type scale
    /// stay as they are.
    public static let stylesheet: String = {
        let theme = HighlightTheme.standard
        return """
        :root {
          color-scheme: light dark;
        \(theme.previewCustomProperties(forDarkAppearance: false))
          --table-fill: rgba(0, 0, 0, 0.06);
          --line: rgba(0, 0, 0, 0.14);
        }
        @media (prefers-color-scheme: dark) {
          :root {
        \(theme.previewCustomProperties(forDarkAppearance: true))
            --table-fill: rgba(255, 255, 255, 0.08);
            --line: rgba(255, 255, 255, 0.16);
          }
        }
        * { box-sizing: border-box; }
        html, body {
          margin: 0;
          min-height: 100%;
          background: canvas;
          color: var(--text);
          font: 15px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
        }
        article {
          box-sizing: border-box;
          width: min(68ch, 100%);
          margin-inline: auto;
          padding: 28px 32px 48px;
        }
        h1, h2, h3, h4, h5, h6 {
          line-height: 1.25;
          letter-spacing: -0.02em;
        }
        h1 { font-size: 2rem; font-weight: 700; margin: 0 0 0.45em; }
        h2 { font-size: 1.55rem; font-weight: 600; margin: 1.15em 0 0.4em; }
        h3 { font-size: 1.28rem; font-weight: 600; margin: 1.1em 0 0.35em; }
        h4 { font-size: 1.1rem; font-weight: 600; margin: 1em 0 0.3em; }
        h5 { font-size: 1rem; font-weight: 600; margin: 1em 0 0.3em; }
        h6 { font-size: 0.92rem; font-weight: 600; margin: 1em 0 0.3em; }
        p { margin: 0 0 0.8em; }
        a { color: var(--link); text-underline-offset: 2px; }
        code {
          font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: 0.9em;
          color: var(--code);
          background: var(--code-fill);
          padding: 0.12em 0.35em;
          border-radius: 5px;
        }
        pre {
          color: var(--code);
          padding: 14px 16px;
          border-radius: 10px;
          overflow: auto;
          margin: 0 0 0.9em;
        }
        pre code { background: none; padding: 0; font-size: 0.86rem; line-height: 1.45; }
        .code-keyword { color: var(--code-keyword); }
        .code-string { color: var(--code-string); }
        .code-number { color: var(--code-number); }
        .code-comment { color: var(--code-comment); }
        .code-type { color: var(--code-type); }
        .code-tag { color: var(--code-tag); }
        .code-attribute { color: var(--code-attribute); }
        blockquote {
          margin: 0 0 0.9em;
          padding: 0.1em 0 0.1em 1em;
          border-left: 3px solid var(--quote-marker);
          color: var(--quote);
        }
        blockquote p:last-child { margin-bottom: 0; }
        ul, ol { margin: 0 0 0.9em; padding-left: 1.4em; }
        li { margin: 0.2em 0; }
        li::marker { color: var(--list-marker); }
        li > ul, li > ol { margin: 0.25em 0 0.2em; }
        li.task { list-style: none; margin-left: -0.2em; }
        li.task input { margin-right: 0.4em; }
        table { border-collapse: collapse; margin: 0 0 1em; width: 100%; }
        th, td { border: 1px solid var(--line); padding: 6px 10px; vertical-align: top; }
        th { font-weight: 600; text-align: left; background: var(--table-fill); }
        hr { border: 0; border-top: 1px solid var(--thematic-break); margin: 1.4em 0; }
        img { max-width: 100%; height: auto; }
        """
    }()

    /// Policy for a document this renderer produced. Page scripts are refused.
    public var contentSecurityPolicy: String {
        let imageSources = imageAddressing == .preview
            ? "\(Self.previewScheme): https: http:"
            : "'self' https: http: file:"
        return "default-src 'none'; img-src \(imageSources); style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; connect-src 'none'; script-src 'none'"
    }

    /// HTML fragment for the document body.
    public func renderBody(_ markdown: String) -> String {
        emitBlocks(MarkdownHTMLParser.blocks(in: markdown), unwrapParagraphs: false)
    }

    /// Complete document, including the default stylesheet.
    public func renderDocument(_ markdown: String, title: String = "") -> String {
        document(wrapping: renderBody(markdown), title: title)
    }

    /// Wraps an already rendered body. The preview uses this for the shell page.
    public func document(wrapping body: String, title: String = "") -> String {
        let safeTitle = escapeText(title.isEmpty ? "Textwork" : title)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <title>\(safeTitle)</title>
        <style>
        \(Self.stylesheet)
        </style>
        </head>
        <body>
        <article id="content">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    /// Resolves a preview image or link path and refuses anything outside `directory`.
    public static func fileURL(forPreviewPath path: String, in directory: URL) -> URL? {
        var relative = path
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        if relative.isEmpty || relative.contains("\0") {
            return nil
        }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.isEmpty || parts.contains(where: { $0 == "." || $0 == ".." }) {
            return nil
        }
        let root = directory.standardizedFileURL
        var candidate = root
        for part in parts {
            candidate.appendPathComponent(part)
        }
        candidate = candidate.standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate
    }

    private func emitBlocks(_ blocks: [MarkdownBlock], unwrapParagraphs: Bool) -> String {
        blocks.map { emitBlock($0, unwrapParagraphs: unwrapParagraphs) }.joined(separator: "\n")
    }

    private func emitBlock(_ block: MarkdownBlock, unwrapParagraphs: Bool) -> String {
        switch block {
        case .heading(let level, let inlines):
            return "<h\(level)>\(emitInlines(inlines))</h\(level)>"
        case .paragraph(let inlines):
            let inner = emitInlines(inlines)
            return unwrapParagraphs ? inner : "<p>\(inner)</p>"
        case .codeBlock(let language, let text):
            let colored = FencedCodeTokenizer.html(for: text, languageName: language)
            if let language {
                return "<pre><code class=\"language-\(escapeAttribute(language))\">\(colored)</code></pre>"
            }
            return "<pre><code>\(colored)</code></pre>"
        case .blockQuote(let children):
            let inner = emitBlocks(children, unwrapParagraphs: false)
            return "<blockquote>\n\(inner)\n</blockquote>"
        case .list(let orderedStart, let tight, let items):
            let tag = orderedStart == nil ? "ul" : "ol"
            var opening = "<\(tag)"
            if let orderedStart, orderedStart != 1 {
                opening += " start=\"\(orderedStart)\""
            }
            opening += ">"
            let body = items.map { emitItem($0, unwrapParagraphs: tight) }.joined(separator: "\n")
            return "\(opening)\n\(body)\n</\(tag)>"
        case .table(let alignments, let header, let rows):
            var html = "<table>\n<thead>\n<tr>"
            for (index, cell) in header.enumerated() {
                let alignment = index < alignments.count ? alignments[index] : .none
                html += "<th\(alignmentAttribute(alignment))>\(emitInlines(cell.inlines))</th>"
            }
            html += "</tr>\n</thead>"
            if !rows.isEmpty {
                html += "\n<tbody>\n"
                for (rowIndex, row) in rows.enumerated() {
                    html += "<tr>"
                    for column in 0..<header.count {
                        let source = column < row.count ? row[column].inlines : []
                        let alignment = column < alignments.count ? alignments[column] : .none
                        html += "<td\(alignmentAttribute(alignment))>\(emitInlines(source))</td>"
                    }
                    html += "</tr>"
                    if rowIndex != rows.count - 1 {
                        html += "\n"
                    }
                }
                html += "\n</tbody>"
            }
            html += "\n</table>"
            return html
        case .thematicBreak:
            return "<hr>"
        }
    }

    private func emitItem(_ item: MarkdownListItem, unwrapParagraphs: Bool) -> String {
        var content = emitBlocks(item.children, unwrapParagraphs: unwrapParagraphs)
        if let checked = item.checked {
            let checkedAttribute = checked ? " checked" : ""
            let checkbox = "<input type=\"checkbox\" disabled\(checkedAttribute)>"
            content = content.isEmpty ? checkbox : checkbox + " " + content
            return "<li class=\"task\">\(content)</li>"
        }
        return "<li>\(content)</li>"
    }

    private func alignmentAttribute(_ alignment: MarkdownTableAlignment) -> String {
        switch alignment {
        case .none:
            return ""
        case .left:
            return " style=\"text-align: left\""
        case .center:
            return " style=\"text-align: center\""
        case .right:
            return " style=\"text-align: right\""
        }
    }

    private func emitInlines(_ inlines: [MarkdownInline]) -> String {
        inlines.map(emitInline).joined()
    }

    private func emitInline(_ inline: MarkdownInline) -> String {
        switch inline {
        case .text(let text):
            return escapeText(text)
        case .softBreak:
            return "\n"
        case .hardBreak:
            return "<br>"
        case .code(let code):
            return "<code>\(escapeRaw(code))</code>"
        case .emphasis(let children):
            return "<em>\(emitInlines(children))</em>"
        case .strong(let children):
            return "<strong>\(emitInlines(children))</strong>"
        case .link(let destination, let title, let children):
            let inner = emitInlines(children)
            guard let href = linkHref(destination) else { return inner }
            if let title, !title.isEmpty {
                return "<a href=\"\(href)\" title=\"\(escapeAttribute(decodeEntities(title)))\">\(inner)</a>"
            }
            return "<a href=\"\(href)\">\(inner)</a>"
        case .image(let destination, let alternativeText):
            guard let source = imageSource(destination) else {
                return escapeText(alternativeText)
            }
            return "<img src=\"\(source)\" alt=\"\(escapeAttribute(decodeEntities(alternativeText)))\">"
        case .unresolvedReference(let match):
            return escapeText(match.opening) + emitInlines(match.children) + escapeText(match.closing)
        }
    }

    private func linkHref(_ destination: String) -> String? {
        let decoded = decodeEntities(destination.trimmingCharacters(in: .whitespacesAndNewlines))
        guard allowedLink(decoded) else { return nil }
        return escapeAttribute(decoded)
    }

    private func imageSource(_ destination: String) -> String? {
        let decoded = decodeEntities(destination.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !decoded.isEmpty, !containsControlCharacter(decoded), !decoded.hasPrefix("//") else { return nil }
        if let scheme = urlScheme(decoded) {
            guard scheme == "http" || scheme == "https" else { return nil }
            return escapeAttribute(decoded)
        }
        switch imageAddressing {
        case .authored:
            return escapeAttribute(decoded)
        case .preview:
            let relative = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
            guard !relative.isEmpty, !relative.hasPrefix("/") else { return nil }
            let encoded = encodePreviewPath(relative)
            return escapeAttribute("\(Self.previewScheme)://\(Self.previewHost)/\(encoded)")
        }
    }

    private func allowedLink(_ destination: String) -> Bool {
        guard !destination.isEmpty, !containsControlCharacter(destination), !destination.hasPrefix("//") else {
            return false
        }
        guard let scheme = urlScheme(destination) else { return true }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    private func encodePreviewPath(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "#?")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}

func escapeText(_ string: String) -> String {
    escapeRaw(decodeEntities(string))
}

func escapeAttribute(_ string: String) -> String {
    escapeRaw(string)
}

func escapeRaw(_ string: String) -> String {
    var result = ""
    result.reserveCapacity(string.count)
    for character in string {
        switch character {
        case "&":
            result.append("&amp;")
        case "<":
            result.append("&lt;")
        case ">":
            result.append("&gt;")
        case "\"":
            result.append("&quot;")
        case "'":
            result.append("&#39;")
        case "\0":
            result.append("\u{FFFD}")
        default:
            result.append(character)
        }
    }
    return result
}

func decodeEntities(_ source: String) -> String {
    guard source.contains("&") else { return source }
    var result = ""
    result.reserveCapacity(source.count)
    var index = source.startIndex
    while index < source.endIndex {
        if source[index] == "&", let (value, next) = entity(in: source, at: index) {
            result.append(value)
            index = next
            continue
        }
        result.append(source[index])
        index = source.index(after: index)
    }
    return result
}

private let namedEntities: [String: String] = [
    "amp": "&",
    "lt": "<",
    "gt": ">",
    "quot": "\"",
    "apos": "'",
    "nbsp": "\u{00A0}",
]

private func entity(in source: String, at start: String.Index) -> (String, String.Index)? {
    var cursor = source.index(after: start)
    guard cursor < source.endIndex else { return nil }
    if source[cursor] == "#" {
        cursor = source.index(after: cursor)
        guard cursor < source.endIndex else { return nil }
        let hexadecimal = source[cursor] == "x" || source[cursor] == "X"
        if hexadecimal {
            cursor = source.index(after: cursor)
        }
        let digitsStart = cursor
        var digits = 0
        while cursor < source.endIndex, digits < 8 {
            let character = source[cursor]
            let isDigit = hexadecimal ? character.isHexDigit : character.isNumber
            if !isDigit { break }
            digits += 1
            cursor = source.index(after: cursor)
        }
        guard digits > 0, cursor < source.endIndex, source[cursor] == ";" else { return nil }
        let text = source[digitsStart..<cursor]
        guard let value = Int(text, radix: hexadecimal ? 16 : 10) else { return nil }
        let next = source.index(after: cursor)
        if value == 0 || !(0...0x10FFFF).contains(value) || (0xD800...0xDFFF).contains(value) {
            return ("\u{FFFD}", next)
        }
        guard let scalar = Unicode.Scalar(value) else {
            return ("\u{FFFD}", next)
        }
        return (String(scalar), next)
    }
    let nameStart = cursor
    var length = 0
    while cursor < source.endIndex, length < 32 {
        let character = source[cursor]
        if !(character.isLetter || character.isNumber) { break }
        length += 1
        cursor = source.index(after: cursor)
    }
    guard length > 0, cursor < source.endIndex, source[cursor] == ";" else { return nil }
    let name = String(source[nameStart..<cursor])
    guard let value = namedEntities[name] else { return nil }
    return (value, source.index(after: cursor))
}

func urlScheme(_ destination: String) -> String? {
    guard let colon = destination.firstIndex(of: ":"), colon > destination.startIndex else { return nil }
    let scheme = destination[..<colon]
    guard let first = scheme.first, isASCIILetter(first) else { return nil }
    for character in scheme {
        if isASCIILetter(character) || character.isNumber || character == "+" || character == "-" || character == "." {
            continue
        }
        return nil
    }
    return scheme.lowercased()
}

func containsControlCharacter(_ string: String) -> Bool {
    string.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
}

func isASCIILetter(_ character: Character) -> Bool {
    guard let value = character.asciiValue else { return false }
    return (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
}

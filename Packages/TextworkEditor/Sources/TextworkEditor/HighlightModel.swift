/// A semantic role a span of raw Markdown source plays while editing.
///
/// `isSyntax` on ``HighlightSpan`` separates punctuation (hashes, backticks,
/// brackets) from the text a reader cares about. Editing mode 2 dims syntax
/// spans. Mode 3 hides them except near the cursor. The prototype paints mode 1:
/// raw source stays visible, and each role gets its own style.
public enum HighlightRole: String, Codable, Sendable, Equatable, CaseIterable {
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case emphasis
    case strong
    case codeSpan
    case codeBlock
    case codeKeyword
    case codeString
    case codeNumber
    case codeComment
    case codeType
    case codeTag
    case codeAttribute
    /// A property or method declared in the surrounding type.
    case codeMember
    /// A property or method that is not declared in the surrounding type.
    case codeOtherMember
    /// An Apple or Swift standard-library type name.
    case codeSystemType
    case link
    case image
    case listMarker
    case blockQuote
    case thematicBreak
    case table
    case html

    public static func heading(level: Int) -> HighlightRole {
        switch level {
        case 1: .heading1
        case 2: .heading2
        case 3: .heading3
        case 4: .heading4
        case 5: .heading5
        default: .heading6
        }
    }
}

/// One styled range in a raw Markdown buffer.
///
/// Offsets are UTF-16 code units, the same coordinate space as `NSRange` /
/// `UITextView`. Ranges never split a UTF-16 surrogate pair when the edit
/// that produced them came from AppKit or UIKit.
public struct HighlightSpan: Codable, Sendable, Equatable, Hashable {
    public var startUTF16: Int
    public var endUTF16: Int
    public var role: HighlightRole
    /// Punctuation rather than content. Modes 2 and 3 key off this flag.
    public var isSyntax: Bool

    public init(startUTF16: Int, endUTF16: Int, role: HighlightRole, isSyntax: Bool) {
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
        self.role = role
        self.isSyntax = isSyntax
    }

    public var utf16Count: Int { endUTF16 - startUTF16 }

    func shifted(by delta: Int) -> HighlightSpan {
        HighlightSpan(
            startUTF16: startUTF16 + delta,
            endUTF16: endUTF16 + delta,
            role: role,
            isSyntax: isSyntax
        )
    }
}

/// A character-boundary edit expressed in UTF-16, matching `NSTextStorage`.
public struct MarkdownEdit: Sendable, Equatable {
    /// Range in the document *before* the edit.
    public var range: Range<Int>
    public var replacement: String

    public init(range: Range<Int>, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

/// How much of the previous block structure an update was able to keep.
public struct HighlightStatistics: Codable, Sendable, Equatable {
    public var blockCount: Int
    public var blocksReparsed: Int
    public var blocksReused: Int

    public init(blockCount: Int, blocksReparsed: Int, blocksReused: Int) {
        self.blockCount = blockCount
        self.blocksReparsed = blocksReparsed
        self.blocksReused = blocksReused
    }
}

/// Highlight state for one document. Pass it back to ``MarkdownHighlighter/apply(_:to:)``.
public struct HighlightSnapshot: Sendable, Equatable {
    public var spans: [HighlightSpan]
    public var statistics: HighlightStatistics
    /// UTF-16 ranges whose attributes can differ from the previous paint.
    ///
    /// A full highlight covers the document. A keystroke covers the restyled
    /// blocks, any block whose reference-link resolution changed, and the
    /// characters the edit inserted. Suffix blocks that were only shifted are
    /// omitted: AppKit and UIKit move their attributes with the text.
    public var invalidatedUTF16Ranges: [Range<Int>]

    var bytes: [UInt8]
    var lines: [TextLine]
    var blocks: [StyledBlock]
    var definedReferenceLabels: Set<String>

    public var utf16Count: Int {
        guard let last = lines.last else { return 0 }
        return last.utf16Start + last.utf16Count + last.newlineUTF16Count
    }
}

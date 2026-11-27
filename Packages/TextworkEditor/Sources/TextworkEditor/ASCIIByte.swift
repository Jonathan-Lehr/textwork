/// ASCII bytes the Markdown scanners compare against.
///
/// Call sites read `ASCIIByte.space` instead of `0x20`.
enum ASCIIByte {
    static let tab: UInt8 = 0x09
    static let lineFeed: UInt8 = 0x0A
    static let verticalTab: UInt8 = 0x0B
    static let formFeed: UInt8 = 0x0C
    static let carriageReturn: UInt8 = 0x0D
    /// Last byte of the C0 control range, before space.
    static let lastControl: UInt8 = 0x1F
    static let space: UInt8 = 0x20
    static let exclamationMark: UInt8 = 0x21
    static let quotationMark: UInt8 = 0x22
    static let hash: UInt8 = 0x23
    static let dollarSign: UInt8 = 0x24
    static let percentSign: UInt8 = 0x25
    static let ampersand: UInt8 = 0x26
    static let apostrophe: UInt8 = 0x27
    static let leftParenthesis: UInt8 = 0x28
    static let rightParenthesis: UInt8 = 0x29
    static let asterisk: UInt8 = 0x2A
    static let plus: UInt8 = 0x2B
    static let comma: UInt8 = 0x2C
    static let hyphen: UInt8 = 0x2D
    static let period: UInt8 = 0x2E
    static let slash: UInt8 = 0x2F
    static let digitZero: UInt8 = 0x30
    static let digitNine: UInt8 = 0x39
    static let colon: UInt8 = 0x3A
    static let semicolon: UInt8 = 0x3B
    static let lessThan: UInt8 = 0x3C
    static let equalsSign: UInt8 = 0x3D
    static let greaterThan: UInt8 = 0x3E
    static let questionMark: UInt8 = 0x3F
    static let atSign: UInt8 = 0x40
    static let uppercaseA: UInt8 = 0x41
    static let uppercaseE: UInt8 = 0x45
    static let uppercaseF: UInt8 = 0x46
    static let uppercaseX: UInt8 = 0x58
    static let uppercaseZ: UInt8 = 0x5A
    static let leftBracket: UInt8 = 0x5B
    static let backslash: UInt8 = 0x5C
    static let rightBracket: UInt8 = 0x5D
    static let caret: UInt8 = 0x5E
    static let underscore: UInt8 = 0x5F
    static let backtick: UInt8 = 0x60
    static let lowercaseA: UInt8 = 0x61
    static let lowercaseE: UInt8 = 0x65
    static let lowercaseF: UInt8 = 0x66
    static let lowercaseX: UInt8 = 0x78
    static let lowercaseZ: UInt8 = 0x7A
    static let leftBrace: UInt8 = 0x7B
    static let verticalBar: UInt8 = 0x7C
    static let rightBrace: UInt8 = 0x7D
    static let tilde: UInt8 = 0x7E
    static let delete: UInt8 = 0x7F
}

/// Masks and prefixes that identify a UTF-8 leading byte.
enum UTF8LeadingByte {
    static let singleByteLimit: UInt8 = 0x80
    static let twoByteMask: UInt8 = 0xE0
    static let twoBytePrefix: UInt8 = 0xC0
    static let threeByteMask: UInt8 = 0xF0
    static let threeBytePrefix: UInt8 = 0xE0
    static let fourByteMask: UInt8 = 0xF8
    static let fourBytePrefix: UInt8 = 0xF0
}

/// Length and indent limits from the Markdown grammar the scanners implement.
enum MarkdownScanLimit {
    /// CommonMark allows at most three spaces before a block marker.
    static let maximumOpeningIndent = 3
    /// An indented code block starts one column past that opening indent.
    static let codeBlockIndent = maximumOpeningIndent + 1
    /// A tab is four columns wide.
    static let tabColumnWidth = 4
    static let maximumHeadingLevel = 6
    /// CommonMark reference labels contain at most 999 Unicode scalars.
    static let maximumReferenceLabelLength = 999
    /// A fence or a thematic break needs at least three marker characters.
    static let minimumMarkerRun = 3
    /// An ordered-list marker holds at most nine digits.
    static let maximumOrderedListMarkerDigits = 9
    /// CommonMark autolink schemes are at most 32 characters.
    static let maximumAutolinkSchemeLength = 32
    /// Named character references scanned by the HTML renderer.
    static let maximumCharacterReferenceNameLength = 32
    /// Digits accepted in one numeric character reference.
    static let maximumNumericCharacterReferenceDigits = 8
}

/// Bounds used when a numeric character reference becomes a Unicode scalar.
enum UnicodeScalarBound {
    static let maximum = 0x10FFFF
    static let surrogateStart = 0xD800
    static let surrogateEnd = 0xDFFF
}

extension UInt8 {
    var isHorizontalSpace: Bool {
        self == ASCIIByte.space || self == ASCIIByte.tab
    }

    var isASCIIDigit: Bool {
        self >= ASCIIByte.digitZero && self <= ASCIIByte.digitNine
    }

    var isASCIILetter: Bool {
        (self >= ASCIIByte.uppercaseA && self <= ASCIIByte.uppercaseZ)
            || (self >= ASCIIByte.lowercaseA && self <= ASCIIByte.lowercaseZ)
    }

    var isASCIIControl: Bool {
        self <= ASCIIByte.lastControl || self == ASCIIByte.delete
    }
}

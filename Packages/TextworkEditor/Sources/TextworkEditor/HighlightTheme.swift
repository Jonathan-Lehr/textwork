import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// sRGB channels from 0 to 255, plus an opacity from 0 to 1.
public struct HighlightColorComponents: Equatable, Sendable, Hashable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: Double

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#RRGGBB` for the preview stylesheet.
    public var cssHex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var unitRed: Double { Double(red) / 255 }
    var unitGreen: Double { Double(green) / 255 }
    var unitBlue: Double { Double(blue) / 255 }
}

/// One color that resolves differently in light and dark appearances.
public struct HighlightColor: Equatable, Sendable, Hashable {
    public var light: HighlightColorComponents
    public var dark: HighlightColorComponents

    public init(light: HighlightColorComponents, dark: HighlightColorComponents) {
        self.light = light
        self.dark = dark
    }
}

/// Content and syntax colors for one highlight role.
public struct HighlightRoleColors: Equatable, Sendable, Hashable {
    public var content: HighlightColor
    public var syntax: HighlightColor

    public init(content: HighlightColor, syntax: HighlightColor) {
        self.content = content
        self.syntax = syntax
    }
}

/// How a span's font differs from the editor's body font.
///
/// Heading size stays in the text view, which knows the configured point size.
/// Emphasis and strong add a trait to the font already painted on that range,
/// so emphasis inside a heading keeps the heading size.
public enum HighlightFontTreatment: Equatable, Sendable {
    case body
    case monospaced
    case heading
    case emphasis
    case strong
}

/// What the text view should paint for one span.
///
/// The only fill is a light gray behind inline code. Indented code and fenced
/// code are a monospaced font and a foreground color.
public struct HighlightRunStyle: Equatable, Sendable {
    public var foreground: HighlightColor
    public var background: HighlightColor?
    public var fontTreatment: HighlightFontTreatment
    public var underline: Bool

    public init(
        foreground: HighlightColor,
        background: HighlightColor?,
        fontTreatment: HighlightFontTreatment,
        underline: Bool
    ) {
        self.foreground = foreground
        self.background = background
        self.fontTreatment = fontTreatment
        self.underline = underline
    }
}

/// Light and dark colors for Markdown highlight roles.
///
/// Syntax markers (`isSyntax`) use a quieter tint of the same hue as the
/// content they mark, so hashes, asterisks, backticks, and brackets stay
/// readable and sit behind the words. Heading, emphasis, strong, and inline
/// code words use the body color. Size, weight, italic, bold, and the inline
/// code chip carry the meaning. Heading markers stay a quieter indigo.
/// Emphasis, strong, and inline code markers are a quieter gray. Reference
/// links use the link role. Unknown fenced languages keep the code color.
/// Swift, JSON, shell, and HTML fences add keyword, string, number, comment,
/// type, tag, and attribute colors from Xcode's Default (Light) and Default
/// (Dark) themes. Tag names use the keyword color, which is how Xcode
/// classifies an HTML tag. Plain code is that theme's plain text at 85 percent
/// opacity, resolved on the editor background. Marker colors are a quieter
/// tint of the same hue. Inline code sits on ``inlineCodeBackground``.
///
/// The text views turn these into dynamic `NSColor` and `UIColor` values, so
/// the same attributes follow the system appearance.
public struct HighlightTheme: Equatable, Sendable {
    public var body: HighlightColor
    /// Gray behind inline code, halfway from the previous chip toward the page.
    /// Light is `#F9F9FA` (halfway from `#F3F3F5` to white). Dark is `#242426`
    /// (halfway from `#2A2A2E` to the `#1E1E1E` editor background).
    public var inlineCodeBackground: HighlightColor
    public var roles: [HighlightRole: HighlightRoleColors]

    /// Approximate system text background the standard palette is tuned against.
    public static let lightEditorBackground = HighlightColorComponents(red: 255, green: 255, blue: 255)
    /// Approximate system text background the standard palette is tuned against.
    public static let darkEditorBackground = HighlightColorComponents(red: 30, green: 30, blue: 30)

    public init(body: HighlightColor, inlineCodeBackground: HighlightColor, roles: [HighlightRole: HighlightRoleColors]) {
        self.body = body
        self.inlineCodeBackground = inlineCodeBackground
        self.roles = roles
    }

    public static let standard: HighlightTheme = {
        let body = highlightColor(light: (0x1D, 0x1D, 0x1F), dark: (0xF5, 0xF5, 0xF7))
        let inlineCodeBackground = highlightColor(light: (0xF9, 0xF9, 0xFA), dark: (0x24, 0x24, 0x26))
        let marker = highlightColor(light: (0x6E, 0x6E, 0x73), dark: (0x98, 0x98, 0x9D))
        let headingSyntax = highlightColor(light: (0x5D, 0x72, 0xB0), dark: (0x77, 0x86, 0xBD))
        let heading = HighlightRoleColors(content: body, syntax: headingSyntax)
        let emphasis = HighlightRoleColors(content: body, syntax: marker)
        let strong = HighlightRoleColors(content: body, syntax: marker)
        // Xcode plain text is black or white at 85 percent opacity.
        // Resolved on white and #1E1E1E so the preview color matches the editor.
        let code = roleColors(
            contentLight: (0x26, 0x26, 0x26),
            contentDark: (0xDD, 0xDD, 0xDD),
            syntaxLight: (0x74, 0x74, 0x74),
            syntaxDark: (0x88, 0x88, 0x88)
        )
        let inlineCode = HighlightRoleColors(content: body, syntax: marker)
        let link = roleColors(
            contentLight: (0x00, 0x66, 0xCC),
            contentDark: (0x41, 0x9C, 0xFF),
            syntaxLight: (0x1C, 0x77, 0xD2),
            syntaxDark: (0x3C, 0x8A, 0xDF)
        )
        let image = roleColors(
            contentLight: (0x08, 0x6E, 0x68),
            contentDark: (0x78, 0xE0, 0xD6),
            syntaxLight: (0x27, 0x80, 0x7B),
            syntaxDark: (0x54, 0x93, 0x8D)
        )
        let quote = roleColors(
            contentLight: (0x40, 0x60, 0x3A),
            contentDark: (0xC6, 0xD8, 0xB0),
            syntaxLight: (0x60, 0x7B, 0x5B),
            syntaxDark: (0x81, 0x8C, 0x74)
        )
        let list = roleColors(
            contentLight: (0x3A, 0x4A, 0x78),
            contentDark: (0xBA, 0xC6, 0xE8),
            syntaxLight: (0x66, 0x73, 0x96),
            syntaxDark: (0x80, 0x88, 0x9D)
        )
        let thematic = roleColors(
            contentLight: (0x3A, 0x3A, 0x3E),
            contentDark: (0xD2, 0xD2, 0xD6),
            syntaxLight: (0x73, 0x73, 0x76),
            syntaxDark: (0x88, 0x88, 0x8B)
        )
        let table = roleColors(
            contentLight: (0x1D, 0x1D, 0x1F),
            contentDark: (0xF5, 0xF5, 0xF7),
            syntaxLight: (0x74, 0x74, 0x75),
            syntaxDark: (0x88, 0x88, 0x89)
        )
        let html = roleColors(
            contentLight: (0x0C, 0x6A, 0x32),
            contentDark: (0x8C, 0xDC, 0xA0),
            syntaxLight: (0x33, 0x82, 0x53),
            syntaxDark: (0x62, 0x93, 0x6E)
        )
        let codeKeyword = roleColors(
            contentLight: (0x9B, 0x23, 0x93),
            contentDark: (0xFC, 0x5F, 0xA3),
            syntaxLight: (0xAE, 0x4E, 0xA8),
            syntaxDark: (0xDF, 0x56, 0x91)
        )
        let codeString = roleColors(
            contentLight: (0xC4, 0x1A, 0x16),
            contentDark: (0xFC, 0x6A, 0x5D),
            syntaxLight: (0xCE, 0x41, 0x3D),
            syntaxDark: (0xDD, 0x60, 0x54)
        )
        let codeNumber = roleColors(
            contentLight: (0x1C, 0x00, 0xCF),
            contentDark: (0xD0, 0xBF, 0x69),
            syntaxLight: (0x71, 0x60, 0xE1),
            syntaxDark: (0x94, 0x89, 0x50)
        )
        // Xcode's dark comment is #6C7986. Lightened so its quieter marker still clears contrast.
        let codeComment = roleColors(
            contentLight: (0x5D, 0x6C, 0x79),
            contentDark: (0x84, 0x95, 0xA5),
            syntaxLight: (0x6C, 0x79, 0x85),
            syntaxDark: (0x77, 0x86, 0x93)
        )
        let codeType = roleColors(
            contentLight: (0x1C, 0x46, 0x4A),
            contentDark: (0x9E, 0xF1, 0xDD),
            syntaxLight: (0x5A, 0x79, 0x7B),
            syntaxDark: (0x64, 0x91, 0x87)
        )
        let codeTag = roleColors(
            contentLight: (0x9B, 0x23, 0x93),
            contentDark: (0xFC, 0x5F, 0xA3),
            syntaxLight: (0xAE, 0x4E, 0xA8),
            syntaxDark: (0xDF, 0x56, 0x91)
        )
        // Xcode's dark attribute is #BF8555. Lightened by one step so its quieter marker still clears contrast.
        let codeAttribute = roleColors(
            contentLight: (0x81, 0x5F, 0x03),
            contentDark: (0xC0, 0x86, 0x55),
            syntaxLight: (0x8E, 0x70, 0x1D),
            syntaxDark: (0xAC, 0x79, 0x4E)
        )
        let roles: [HighlightRole: HighlightRoleColors] = [
            .heading1: heading,
            .heading2: heading,
            .heading3: heading,
            .heading4: heading,
            .heading5: heading,
            .heading6: heading,
            .emphasis: emphasis,
            .strong: strong,
            .codeSpan: inlineCode,
            .codeBlock: code,
            .codeKeyword: codeKeyword,
            .codeString: codeString,
            .codeNumber: codeNumber,
            .codeComment: codeComment,
            .codeType: codeType,
            .codeTag: codeTag,
            .codeAttribute: codeAttribute,
            .link: link,
            .image: image,
            .listMarker: list,
            .blockQuote: quote,
            .thematicBreak: thematic,
            .table: table,
            .html: html,
        ]
        for role in HighlightRole.allCases {
            precondition(roles[role] != nil, "Highlight theme is missing \(role.rawValue)")
        }
        return HighlightTheme(body: body, inlineCodeBackground: inlineCodeBackground, roles: roles)
    }()

    public func colors(for role: HighlightRole) -> HighlightRoleColors {
        roles[role] ?? HighlightRoleColors(content: body, syntax: body)
    }

    public func color(for role: HighlightRole, isSyntax: Bool) -> HighlightColor {
        let colors = colors(for: role)
        return isSyntax ? colors.syntax : colors.content
    }

    /// Fill behind a span. Inline code returns ``inlineCodeBackground``.
    /// Indented code and fenced code return nil.
    public func backgroundColor(for role: HighlightRole, isSyntax: Bool) -> HighlightColor? {
        runStyle(for: role, isSyntax: isSyntax).background
    }

    /// Foreground, font treatment, and underline for one span.
    ///
    /// Content is painted before syntax, so a marker's style wins on its own
    /// range. Emphasis and strong keep whatever font is already on the range
    /// and add a trait.
    public func runStyle(for role: HighlightRole, isSyntax: Bool) -> HighlightRunStyle {
        let foreground = color(for: role, isSyntax: isSyntax)
        if isSyntax {
            let treatment: HighlightFontTreatment = (role == .codeSpan || role == .codeBlock) ? .monospaced : .body
            return HighlightRunStyle(
                foreground: foreground,
                background: nil,
                fontTreatment: treatment,
                underline: false
            )
        }
        switch role {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return HighlightRunStyle(foreground: foreground, background: nil, fontTreatment: .heading, underline: false)
        case .emphasis:
            return HighlightRunStyle(foreground: foreground, background: nil, fontTreatment: .emphasis, underline: false)
        case .strong:
            return HighlightRunStyle(foreground: foreground, background: nil, fontTreatment: .strong, underline: false)
        case .codeSpan:
            return HighlightRunStyle(
                foreground: foreground,
                background: inlineCodeBackground,
                fontTreatment: .monospaced,
                underline: false
            )
        case .codeBlock, .html, .codeKeyword, .codeString, .codeNumber, .codeComment, .codeType, .codeTag, .codeAttribute:
            return HighlightRunStyle(foreground: foreground, background: nil, fontTreatment: .monospaced, underline: false)
        case .link, .image:
            return HighlightRunStyle(foreground: foreground, background: nil, fontTreatment: .body, underline: true)
        case .listMarker, .blockQuote, .thematicBreak, .table:
            return HighlightRunStyle(foreground: foreground, background: nil, fontTreatment: .body, underline: false)
        }
    }

    /// Custom properties for the preview stylesheet. Content colors style the
    /// rendered words. Marker colors style the quote rule, list bullets, and
    /// the horizontal rule. The preview escapes raw HTML, so it has no element
    /// for the html role.
    func previewCustomProperties(forDarkAppearance dark: Bool) -> String {
        let entries: [(String, HighlightColor)] = [
            ("--text", body),
            ("--code", color(for: .codeBlock, isSyntax: false)),
            ("--code-fill", inlineCodeBackground),
            ("--code-keyword", color(for: .codeKeyword, isSyntax: false)),
            ("--code-string", color(for: .codeString, isSyntax: false)),
            ("--code-number", color(for: .codeNumber, isSyntax: false)),
            ("--code-comment", color(for: .codeComment, isSyntax: false)),
            ("--code-type", color(for: .codeType, isSyntax: false)),
            ("--code-tag", color(for: .codeTag, isSyntax: false)),
            ("--code-attribute", color(for: .codeAttribute, isSyntax: false)),
            ("--link", color(for: .link, isSyntax: false)),
            ("--quote", color(for: .blockQuote, isSyntax: false)),
            ("--quote-marker", color(for: .blockQuote, isSyntax: true)),
            ("--list-marker", color(for: .listMarker, isSyntax: true)),
            ("--thematic-break", color(for: .thematicBreak, isSyntax: true)),
        ]
        return entries.map { name, color in
            let hex = dark ? color.dark.cssHex : color.light.cssHex
            return "  \(name): \(hex);"
        }.joined(separator: "\n")
    }
}

private func highlightColor(light: (UInt8, UInt8, UInt8), dark: (UInt8, UInt8, UInt8)) -> HighlightColor {
    HighlightColor(
        light: HighlightColorComponents(red: light.0, green: light.1, blue: light.2),
        dark: HighlightColorComponents(red: dark.0, green: dark.1, blue: dark.2)
    )
}

private func roleColors(
    contentLight: (UInt8, UInt8, UInt8),
    contentDark: (UInt8, UInt8, UInt8),
    syntaxLight: (UInt8, UInt8, UInt8),
    syntaxDark: (UInt8, UInt8, UInt8)
) -> HighlightRoleColors {
    HighlightRoleColors(
        content: highlightColor(light: contentLight, dark: contentDark),
        syntax: highlightColor(light: syntaxLight, dark: syntaxDark)
    )
}

#if canImport(AppKit)
public typealias HighlightPlatformColor = NSColor
#elseif canImport(UIKit)
public typealias HighlightPlatformColor = UIColor
#endif

#if canImport(AppKit) || canImport(UIKit)
extension HighlightTheme {
    /// Dynamic color for an arbitrary theme color. Standard colors are cached.
    public func platformColor(_ color: HighlightColor) -> HighlightPlatformColor {
        HighlightPlatformColorCache.shared.color(for: color)
    }

    public func platformColor(for role: HighlightRole, isSyntax: Bool) -> HighlightPlatformColor {
        platformColor(color(for: role, isSyntax: isSyntax))
    }

    public var bodyPlatformColor: HighlightPlatformColor {
        platformColor(body)
    }
}

extension HighlightColor {
    func makeDynamicPlatformColor() -> HighlightPlatformColor {
        let lightComponents = light
        let darkComponents = dark
        #if canImport(AppKit)
        return NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let components = isDark ? darkComponents : lightComponents
            return NSColor(
                srgbRed: CGFloat(components.unitRed),
                green: CGFloat(components.unitGreen),
                blue: CGFloat(components.unitBlue),
                alpha: CGFloat(components.alpha)
            )
        })
        #elseif canImport(UIKit)
        return UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? darkComponents : lightComponents
            return UIColor(
                red: CGFloat(components.unitRed),
                green: CGFloat(components.unitGreen),
                blue: CGFloat(components.unitBlue),
                alpha: CGFloat(components.alpha)
            )
        }
        #endif
    }
}

private final class HighlightPlatformColorCache: @unchecked Sendable {
    static let shared: HighlightPlatformColorCache = {
        let theme = HighlightTheme.standard
        var stored: [HighlightColor: HighlightPlatformColor] = [:]
        func store(_ color: HighlightColor) {
            stored[color] = color.makeDynamicPlatformColor()
        }
        store(theme.body)
        for role in HighlightRole.allCases {
            store(theme.color(for: role, isSyntax: false))
            store(theme.color(for: role, isSyntax: true))
        }
        return HighlightPlatformColorCache(colors: stored)
    }()

    /// Filled once before the cache is published. Readers do not mutate it.
    private let colors: [HighlightColor: HighlightPlatformColor]

    private init(colors: [HighlightColor: HighlightPlatformColor]) {
        self.colors = colors
    }

    func color(for color: HighlightColor) -> HighlightPlatformColor {
        colors[color] ?? color.makeDynamicPlatformColor()
    }
}
#endif

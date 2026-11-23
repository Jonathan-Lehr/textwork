import CoreGraphics
import Foundation
import TextworkEditor

/// Typography the editor shows.
///
/// The standard face is Menlo at the platform's default size, with two points
/// of extra line spacing. `fontSize` stays optional so a preference can replace
/// that size later. When Menlo cannot be loaded, the editor uses the system
/// monospaced font. Line and paragraph spacing are points added to the font's
/// built-in spacing.
struct EditorTypography: Equatable, Sendable {
    var fontName: String?
    var fontSize: CGFloat?
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat

    static let menloFontName = "Menlo"

    static let standard = EditorTypography(
        fontName: menloFontName,
        fontSize: nil,
        lineSpacing: 2,
        paragraphSpacing: 0
    )

    static func menloPostScriptName(bold: Bool, italic: Bool) -> String {
        switch (bold, italic) {
        case (false, false):
            "Menlo-Regular"
        case (true, false):
            "Menlo-Bold"
        case (false, true):
            "Menlo-Italic"
        case (true, true):
            "Menlo-BoldItalic"
        }
    }

    /// Which face to load. A missing Menlo request falls back to the system
    /// monospaced font. Any other missing name falls back to the system font.
    static func fontSource(fontName: String?, nameIsAvailable: Bool) -> EditorFontSource {
        if let fontName, nameIsAvailable {
            return .named(fontName)
        }
        if fontName == menloFontName {
            return .systemMonospaced
        }
        return .system
    }
}

enum EditorFontSource: Equatable {
    case named(String)
    case systemMonospaced
    case system
}

/// Values shared by the Mac text view and the iPad text view.
///
/// This is ordinary Swift. There is no plist, JSON, or other runtime file.
/// `theme` is the light and dark palette the highlighter's roles paint with.
struct EditorConfiguration: Equatable, Sendable {
    var typography: EditorTypography
    var theme: HighlightTheme
    var horizontalInset: CGFloat
    var verticalInset: CGFloat
    /// When false, the text view does not rewrite quotes, dashes, or links as the user types.
    var allowsAutomaticSubstitution: Bool
    var allowsSpellingCorrection: Bool

    static let standard = EditorConfiguration(
        typography: .standard,
        theme: .standard,
        horizontalInset: 8,
        verticalInset: 12,
        allowsAutomaticSubstitution: false,
        allowsSpellingCorrection: false
    )
}

#if os(macOS)
import AppKit

extension EditorConfiguration {
    @MainActor
    func apply(to textView: NSTextView) {
        let attributes = baseAttributes()
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = allowsAutomaticSubstitution
        textView.isAutomaticDashSubstitutionEnabled = allowsAutomaticSubstitution
        textView.isAutomaticDataDetectionEnabled = allowsAutomaticSubstitution
        textView.isAutomaticLinkDetectionEnabled = allowsAutomaticSubstitution
        textView.isAutomaticTextReplacementEnabled = allowsAutomaticSubstitution
        textView.isAutomaticSpellingCorrectionEnabled = allowsSpellingCorrection
        textView.isContinuousSpellCheckingEnabled = allowsSpellingCorrection
        if allowsSpellingCorrection {
            textView.enabledTextCheckingTypes = NSTextCheckingTypes(NSTextCheckingResult.CheckingType.spelling.rawValue)
        } else {
            textView.enabledTextCheckingTypes = 0
        }
        textView.font = bodyFont()
        textView.textColor = theme.bodyPlatformColor
        textView.defaultParagraphStyle = paragraphStyle()
        textView.typingAttributes = attributes
        textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont(),
            .foregroundColor: theme.bodyPlatformColor,
            .paragraphStyle: paragraphStyle(),
        ]
    }

    func bodyFont() -> NSFont {
        font(ofSize: resolvedFontSize)
    }

    func monospacedFont() -> NSFont {
        if typography.fontName == EditorTypography.menloFontName {
            return font(ofSize: resolvedFontSize)
        }
        return NSFont.monospacedSystemFont(ofSize: resolvedFontSize, weight: .regular)
    }

    func boldFont(ofSize size: CGFloat) -> NSFont {
        if typography.fontName == EditorTypography.menloFontName {
            if let face = menloFont(ofSize: size, bold: true, italic: false) {
                return face
            }
            return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        }
        return NSFontManager.shared.convert(font(ofSize: size), toHaveTrait: .boldFontMask)
    }

    func fontAddingBold(to font: NSFont) -> NSFont {
        let italic = NSFontManager.shared.traits(of: font).contains(.italicFontMask)
        if let face = menloFont(matching: font, bold: true, italic: italic) {
            return face
        }
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    func fontAddingItalic(to font: NSFont) -> NSFont {
        let bold = NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        if let face = menloFont(matching: font, bold: bold, italic: true) {
            return face
        }
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    func font(ofSize size: CGFloat) -> NSFont {
        let loaded = typography.fontName.flatMap { NSFont(name: $0, size: size) }
        switch EditorTypography.fontSource(fontName: typography.fontName, nameIsAvailable: loaded != nil) {
        case .named:
            return loaded ?? NSFont.systemFont(ofSize: size)
        case .systemMonospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .system:
            return NSFont.systemFont(ofSize: size)
        }
    }

    private func menloFont(matching font: NSFont, bold: Bool, italic: Bool) -> NSFont? {
        guard font.familyName == EditorTypography.menloFontName else { return nil }
        return menloFont(ofSize: font.pointSize, bold: bold, italic: italic)
    }

    private func menloFont(ofSize size: CGFloat, bold: Bool, italic: Bool) -> NSFont? {
        NSFont(name: EditorTypography.menloPostScriptName(bold: bold, italic: italic), size: size)
    }

    func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = typography.lineSpacing
        style.paragraphSpacing = typography.paragraphSpacing
        return style
    }

    var resolvedFontSize: CGFloat {
        typography.fontSize ?? NSFont.systemFontSize
    }
}
#else
import UIKit

extension EditorConfiguration {
    @MainActor
    func apply(to textView: UITextView) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.smartQuotesType = allowsAutomaticSubstitution ? .default : .no
        textView.smartDashesType = allowsAutomaticSubstitution ? .default : .no
        textView.smartInsertDeleteType = allowsAutomaticSubstitution ? .default : .no
        textView.autocorrectionType = allowsSpellingCorrection ? .default : .no
        textView.spellCheckingType = allowsSpellingCorrection ? .default : .no
        textView.font = bodyFont()
        textView.textColor = theme.bodyPlatformColor
        textView.typingAttributes = baseAttributes()
        textView.textContainerInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont(),
            .foregroundColor: theme.bodyPlatformColor,
            .paragraphStyle: paragraphStyle(),
        ]
    }

    func bodyFont() -> UIFont {
        if typography.fontName == nil, typography.fontSize == nil {
            return UIFont.preferredFont(forTextStyle: .body)
        }
        return font(ofSize: resolvedFontSize)
    }

    func monospacedFont() -> UIFont {
        if typography.fontName == EditorTypography.menloFontName {
            return font(ofSize: resolvedFontSize)
        }
        return UIFont.monospacedSystemFont(ofSize: resolvedFontSize, weight: .regular)
    }

    func boldFont(ofSize size: CGFloat) -> UIFont {
        if typography.fontName == EditorTypography.menloFontName {
            if let face = menloFont(ofSize: size, bold: true, italic: false) {
                return face
            }
            return UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        }
        return addingSymbolicTrait(.traitBold, to: font(ofSize: size))
    }

    func fontAddingBold(to font: UIFont) -> UIFont {
        let italic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        if let face = menloFont(matching: font, bold: true, italic: italic) {
            return face
        }
        return addingSymbolicTrait(.traitBold, to: font)
    }

    func fontAddingItalic(to font: UIFont) -> UIFont {
        let bold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
        if let face = menloFont(matching: font, bold: bold, italic: true) {
            return face
        }
        return addingSymbolicTrait(.traitItalic, to: font)
    }

    func font(ofSize size: CGFloat) -> UIFont {
        let loaded = typography.fontName.flatMap { UIFont(name: $0, size: size) }
        switch EditorTypography.fontSource(fontName: typography.fontName, nameIsAvailable: loaded != nil) {
        case .named:
            return loaded ?? UIFont.systemFont(ofSize: size)
        case .systemMonospaced:
            return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .system:
            return UIFont.systemFont(ofSize: size)
        }
    }

    private func menloFont(matching font: UIFont, bold: Bool, italic: Bool) -> UIFont? {
        guard font.familyName == EditorTypography.menloFontName else { return nil }
        return menloFont(ofSize: font.pointSize, bold: bold, italic: italic)
    }

    private func menloFont(ofSize size: CGFloat, bold: Bool, italic: Bool) -> UIFont? {
        UIFont(name: EditorTypography.menloPostScriptName(bold: bold, italic: italic), size: size)
    }

    private func addingSymbolicTrait(_ trait: UIFontDescriptor.SymbolicTraits, to font: UIFont) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(trait)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = typography.lineSpacing
        style.paragraphSpacing = typography.paragraphSpacing
        return style
    }

    var resolvedFontSize: CGFloat {
        typography.fontSize ?? UIFont.preferredFont(forTextStyle: .body).pointSize
    }
}
#endif

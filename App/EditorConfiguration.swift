import CoreGraphics
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
        case (false, false): "Menlo-Regular"
        case (true, false): "Menlo-Bold"
        case (false, true): "Menlo-Italic"
        case (true, true): "Menlo-BoldItalic"
        }
    }

    /// Which face to load. A missing Menlo request falls back to the system
    /// monospaced font. Any other missing name falls back to the system font.
    static func fontSource(fontName: String?, nameIsAvailable: Bool) -> EditorFontSource {
        if let fontName, nameIsAvailable { return .named(fontName) }
        if fontName == menloFontName { return .systemMonospaced }
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

extension NSFont {
    static func menlo(ofSize size: CGFloat, bold: Bool, italic: Bool) -> NSFont? {
        NSFont(name: EditorTypography.menloPostScriptName(bold: bold, italic: italic), size: size)
    }

    func addingBold() -> NSFont {
        let italic = NSFontManager.shared.traits(of: self).contains(.italicFontMask)
        if let menlo = menloFace(bold: true, italic: italic) { return menlo }
        return NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }

    func addingItalic() -> NSFont {
        let bold = NSFontManager.shared.traits(of: self).contains(.boldFontMask)
        if let menlo = menloFace(bold: bold, italic: true) { return menlo }
        return NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    }

    private func menloFace(bold: Bool, italic: Bool) -> NSFont? {
        guard familyName == EditorTypography.menloFontName else { return nil }
        return NSFont.menlo(ofSize: pointSize, bold: bold, italic: italic)
    }
}

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
        if typography.fontName == EditorTypography.menloFontName { return font(ofSize: resolvedFontSize) }
        return NSFont.monospacedSystemFont(ofSize: resolvedFontSize, weight: .regular)
    }

    func boldFont(ofSize size: CGFloat) -> NSFont {
        if typography.fontName == EditorTypography.menloFontName {
            if let face = NSFont.menlo(ofSize: size, bold: true, italic: false) { return face }
            return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        }
        return NSFontManager.shared.convert(font(ofSize: size), toHaveTrait: .boldFontMask)
    }

    func font(ofSize size: CGFloat) -> NSFont {
        let loaded = typography.fontName.flatMap { NSFont(name: $0, size: size) }
        switch EditorTypography.fontSource(fontName: typography.fontName, nameIsAvailable: loaded != nil) {
        case .named: return loaded ?? NSFont.systemFont(ofSize: size)
        case .systemMonospaced: return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .system: return NSFont.systemFont(ofSize: size)
        }
    }

    var resolvedFontSize: CGFloat {
        typography.fontSize ?? NSFont.systemFontSize
    }
}
#else
import UIKit

extension UIFont {
    static func menlo(ofSize size: CGFloat, bold: Bool, italic: Bool) -> UIFont? {
        UIFont(name: EditorTypography.menloPostScriptName(bold: bold, italic: italic), size: size)
    }

    func addingBold() -> UIFont {
        let italic = fontDescriptor.symbolicTraits.contains(.traitItalic)
        if let menlo = menloFace(bold: true, italic: italic) { return menlo }
        return addingSymbolicTrait(.traitBold)
    }

    func addingItalic() -> UIFont {
        let bold = fontDescriptor.symbolicTraits.contains(.traitBold)
        if let menlo = menloFace(bold: bold, italic: true) { return menlo }
        return addingSymbolicTrait(.traitItalic)
    }

    private func menloFace(bold: Bool, italic: Bool) -> UIFont? {
        guard familyName == EditorTypography.menloFontName else { return nil }
        return UIFont.menlo(ofSize: pointSize, bold: bold, italic: italic)
    }

    private func addingSymbolicTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        traits.insert(trait)
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

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
        if typography.fontName == EditorTypography.menloFontName { return font(ofSize: resolvedFontSize) }
        return UIFont.monospacedSystemFont(ofSize: resolvedFontSize, weight: .regular)
    }

    func boldFont(ofSize size: CGFloat) -> UIFont {
        if typography.fontName == EditorTypography.menloFontName {
            if let face = UIFont.menlo(ofSize: size, bold: true, italic: false) { return face }
            return UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        }
        return font(ofSize: size).addingBold()
    }

    func font(ofSize size: CGFloat) -> UIFont {
        let loaded = typography.fontName.flatMap { UIFont(name: $0, size: size) }
        switch EditorTypography.fontSource(fontName: typography.fontName, nameIsAvailable: loaded != nil) {
        case .named: return loaded ?? UIFont.systemFont(ofSize: size)
        case .systemMonospaced: return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .system: return UIFont.systemFont(ofSize: size)
        }
    }

    var resolvedFontSize: CGFloat {
        typography.fontSize ?? UIFont.preferredFont(forTextStyle: .body).pointSize
    }
}
#endif

extension NSParagraphStyle {
    static func with(lineSpacing: CGFloat, paragraphSpacing: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        return style
    }
}

extension EditorConfiguration {
    func paragraphStyle() -> NSParagraphStyle {
        NSParagraphStyle.with(
            lineSpacing: typography.lineSpacing,
            paragraphSpacing: typography.paragraphSpacing
        )
    }
}

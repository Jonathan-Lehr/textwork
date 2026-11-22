import CoreGraphics
import Foundation
import TextworkEditor

/// Typography the editor can show today and that preferences can replace later.
///
/// `fontName` and `fontSize` are optional so the platform body font stays in
/// effect until a preference chooses otherwise. Line and paragraph spacing are
/// points added to the font's built-in spacing.
struct EditorTypography: Equatable, Sendable {
    var fontName: String?
    var fontSize: CGFloat?
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat

    static let standard = EditorTypography(
        fontName: nil,
        fontSize: nil,
        lineSpacing: 0,
        paragraphSpacing: 0
    )
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
        NSFont.monospacedSystemFont(ofSize: resolvedFontSize, weight: .regular)
    }

    func font(ofSize size: CGFloat) -> NSFont {
        if let fontName = typography.fontName, let named = NSFont(name: fontName, size: size) {
            return named
        }
        return NSFont.systemFont(ofSize: size)
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
        UIFont.monospacedSystemFont(ofSize: resolvedFontSize, weight: .regular)
    }

    func font(ofSize size: CGFloat) -> UIFont {
        if let fontName = typography.fontName, let named = UIFont(name: fontName, size: size) {
            return named
        }
        return UIFont.systemFont(ofSize: size)
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

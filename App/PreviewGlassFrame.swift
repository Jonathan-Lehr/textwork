import SwiftUI
import TextworkEditor

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared geometry for the preview card and the glass frame around it.
enum PreviewCardLayout {
    static let cornerRadius: CGFloat = 12
    static let glassFrameThickness: CGFloat = 8
    static let outerPadding: CGFloat = 16

    static var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

/// The card's rounded rectangle with the middle removed.
///
/// The hole is the article. Glass drawn in this shape stays on the edge, so
/// the rendered words are not under the material.
struct RoundedRectangleFrame: Shape {
    var cornerRadius: CGFloat
    var thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let outer = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        let inset = rect.insetBy(dx: thickness, dy: thickness)
        guard inset.width > 0, inset.height > 0 else { return outer }
        let innerRadius = max(cornerRadius - thickness, 0)
        let inner = RoundedRectangle(cornerRadius: innerRadius, style: .continuous).path(in: inset)
        return outer.subtracting(inner)
    }
}

/// Liquid Glass rim around the preview, or the hairline stroke on earlier systems.
///
/// The rim does not take part in hit testing. Selection, scrolling, and link
/// clicks stay with the web view underneath, including along the edge.
struct PreviewGlassFrame: View {
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(
                    .regular,
                    in: RoundedRectangleFrame(
                        cornerRadius: PreviewCardLayout.cornerRadius,
                        thickness: PreviewCardLayout.glassFrameThickness
                    )
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            PreviewCardLayout.card
                .strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Fill behind the preview page.
///
/// macOS 26 and iOS 26 drop the gray wash. The page uses the opaque background
/// the highlight palette is tuned against, and ``PreviewGlassFrame`` marks the
/// card. Earlier systems keep the translucent wash and the hairline stroke.
enum PreviewSurface {
    static var usesGlassFrame: Bool {
        if #available(macOS 26.0, iOS 26.0, *) {
            return true
        }
        return false
    }

    static var pageSurface: MarkdownPageSurface {
        usesGlassFrame ? .editorBackground : .translucentWash
    }

    static var cardBackground: Color {
        if usesGlassFrame {
            #if os(macOS)
            return Color(nsColor: underPageBackgroundColor)
            #else
            return Color(uiColor: underPageBackgroundColor)
            #endif
        }
        return Color.primary.opacity(0.05)
    }

    #if os(macOS)
    static var underPageBackgroundColor: NSColor {
        if usesGlassFrame {
            return editorBackgroundColor
        }
        return NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: 1, alpha: 0.06)
                : NSColor(calibratedWhite: 0, alpha: 0.05)
        })
    }

    private static var editorBackgroundColor: NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            let components = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? HighlightTheme.darkEditorBackground
                : HighlightTheme.lightEditorBackground
            return platformColor(components)
        })
    }

    private static func platformColor(_ components: HighlightColorComponents) -> NSColor {
        NSColor(
            srgbRed: CGFloat(components.red) / 255,
            green: CGFloat(components.green) / 255,
            blue: CGFloat(components.blue) / 255,
            alpha: CGFloat(components.alpha)
        )
    }
    #else
    static var underPageBackgroundColor: UIColor {
        if usesGlassFrame {
            return editorBackgroundColor
        }
        return .clear
    }

    private static var editorBackgroundColor: UIColor {
        UIColor { traits in
            let components = traits.userInterfaceStyle == .dark
                ? HighlightTheme.darkEditorBackground
                : HighlightTheme.lightEditorBackground
            return UIColor(
                red: CGFloat(components.red) / 255,
                green: CGFloat(components.green) / 255,
                blue: CGFloat(components.blue) / 255,
                alpha: CGFloat(components.alpha)
            )
        }
    }
    #endif
}

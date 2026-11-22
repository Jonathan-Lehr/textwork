import SwiftUI
import TextworkEditor

#if os(macOS)
import AppKit

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.enabledTextCheckingTypes = []
        textView.font = HighlightColors.baseFont
        textView.textColor = HighlightColors.label
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.documentView = textView
        context.coordinator.replaceAll(text, in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text, !context.coordinator.isApplyingHighlight else { return }
        context.coordinator.replaceAll(text, in: textView)
    }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        @Binding var text: String
        let highlighter = MarkdownHighlighter()
        var snapshot: HighlightSnapshot
        var isApplyingHighlight = false

        init(text: Binding<String>) {
            _text = text
            snapshot = highlighter.highlight(text.wrappedValue)
        }

        func replaceAll(_ replacement: String, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            isApplyingHighlight = true
            storage.setAttributedString(NSAttributedString(string: replacement))
            snapshot = highlighter.highlight(replacement)
            paint(snapshot.spans, in: storage)
            isApplyingHighlight = false
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), !isApplyingHighlight else { return }
            let newLength = editedRange.length
            let oldLength = newLength - delta
            guard oldLength >= 0 else { return }
            let oldRange = editedRange.location..<(editedRange.location + oldLength)
            let replacement = (textStorage.string as NSString).substring(with: editedRange)
            snapshot = highlighter.apply(MarkdownEdit(range: oldRange, replacement: replacement), to: snapshot)
            isApplyingHighlight = true
            paint(snapshot.spans, in: textStorage)
            isApplyingHighlight = false
            text = textStorage.string
        }

        private func paint(_ spans: [HighlightSpan], in storage: NSTextStorage) {
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.undoManager?.disableUndoRegistration()
            storage.beginEditing()
            storage.setAttributes(HighlightColors.baseAttributes, range: fullRange)
            for span in spans where !span.isSyntax {
                HighlightColors.applyContent(span, to: storage)
            }
            for span in spans where span.isSyntax {
                HighlightColors.applySyntax(span, to: storage)
            }
            storage.endEditing()
            storage.undoManager?.enableUndoRegistration()
        }
    }
}

private enum HighlightColors {
    static var baseFont: NSFont { NSFont.systemFont(ofSize: NSFont.systemFontSize) }
    static var monospacedFont: NSFont { NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) }
    static var label: NSColor { NSColor.labelColor }
    static var syntax: NSColor { NSColor.tertiaryLabelColor }
    static var link: NSColor { NSColor.linkColor }
    static var codeBackground: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.35) }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: label]
    }

    static func applyContent(_ span: HighlightSpan, to storage: NSTextStorage) {
        guard let range = nsRange(span, length: storage.length) else { return }
        var font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? baseFont
        let manager = NSFontManager.shared
        switch span.role {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            let size = NSFont.systemFontSize + headingBoost(span.role)
            font = NSFont.systemFont(ofSize: size, weight: .bold)
        case .emphasis:
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        case .strong:
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        case .codeSpan, .codeBlock:
            font = monospacedFont
            storage.addAttribute(.backgroundColor, value: codeBackground, range: range)
        case .link, .image:
            storage.addAttribute(.foregroundColor, value: link, range: range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .table:
            break
        case .listMarker, .blockQuote, .thematicBreak:
            break
        }
        storage.addAttribute(.font, value: font, range: range)
    }

    static func applySyntax(_ span: HighlightSpan, to storage: NSTextStorage) {
        guard let range = nsRange(span, length: storage.length) else { return }
        storage.addAttributes(
            [.font: baseFont, .foregroundColor: syntax],
            range: range
        )
    }

    static func headingBoost(_ role: HighlightRole) -> CGFloat {
        switch role {
        case .heading1: 8
        case .heading2: 5
        case .heading3: 3
        case .heading4: 2
        default: 1
        }
    }

    static func nsRange(_ span: HighlightSpan, length: Int) -> NSRange? {
        guard span.startUTF16 >= 0, span.endUTF16 <= length, span.endUTF16 > span.startUTF16 else { return nil }
        return NSRange(location: span.startUTF16, length: span.endUTF16 - span.startUTF16)
    }
}

#else
import UIKit

struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = true
        textView.isSelectable = true
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.font = HighlightColors.baseFont
        textView.textColor = HighlightColors.label
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.textStorage.delegate = context.coordinator
        context.coordinator.replaceAll(text, in: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.text != text, !context.coordinator.isApplyingHighlight else { return }
        context.coordinator.replaceAll(text, in: textView)
    }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        @Binding var text: String
        let highlighter = MarkdownHighlighter()
        var snapshot: HighlightSnapshot
        var isApplyingHighlight = false

        init(text: Binding<String>) {
            _text = text
            snapshot = highlighter.highlight(text.wrappedValue)
        }

        func replaceAll(_ replacement: String, in textView: UITextView) {
            let storage = textView.textStorage
            isApplyingHighlight = true
            storage.setAttributedString(NSAttributedString(string: replacement))
            snapshot = highlighter.highlight(replacement)
            paint(snapshot.spans, in: storage)
            isApplyingHighlight = false
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), !isApplyingHighlight else { return }
            let oldLength = editedRange.length - delta
            guard oldLength >= 0 else { return }
            let oldRange = editedRange.location..<(editedRange.location + oldLength)
            let replacement = (textStorage.string as NSString).substring(with: editedRange)
            snapshot = highlighter.apply(MarkdownEdit(range: oldRange, replacement: replacement), to: snapshot)
            isApplyingHighlight = true
            paint(snapshot.spans, in: textStorage)
            isApplyingHighlight = false
            text = textStorage.string
        }

        private func paint(_ spans: [HighlightSpan], in storage: NSTextStorage) {
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.undoManager?.disableUndoRegistration()
            storage.beginEditing()
            storage.setAttributes(HighlightColors.baseAttributes, range: fullRange)
            for span in spans where !span.isSyntax {
                HighlightColors.applyContent(span, to: storage)
            }
            for span in spans where span.isSyntax {
                HighlightColors.applySyntax(span, to: storage)
            }
            storage.endEditing()
            storage.undoManager?.enableUndoRegistration()
        }
    }
}

private enum HighlightColors {
    static var baseFont: UIFont { UIFont.preferredFont(forTextStyle: .body) }
    static var monospacedFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
    }
    static var label: UIColor { UIColor.label }
    static var syntax: UIColor { UIColor.tertiaryLabel }
    static var link: UIColor { UIColor.link }
    static var codeBackground: UIColor { UIColor.tertiarySystemFill }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: label]
    }

    static func applyContent(_ span: HighlightSpan, to storage: NSTextStorage) {
        guard let range = nsRange(span, length: storage.length) else { return }
        var font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont) ?? baseFont
        switch span.role {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            font = UIFont.systemFont(ofSize: baseFont.pointSize + headingBoost(span.role), weight: .bold)
        case .emphasis:
            font = adding(.traitItalic, to: font)
        case .strong:
            font = adding(.traitBold, to: font)
        case .codeSpan, .codeBlock:
            font = monospacedFont
            storage.addAttribute(.backgroundColor, value: codeBackground, range: range)
        case .link, .image:
            storage.addAttribute(.foregroundColor, value: link, range: range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .table, .listMarker, .blockQuote, .thematicBreak:
            break
        }
        storage.addAttribute(.font, value: font, range: range)
    }

    static func applySyntax(_ span: HighlightSpan, to storage: NSTextStorage) {
        guard let range = nsRange(span, length: storage.length) else { return }
        storage.addAttributes([.font: baseFont, .foregroundColor: syntax], range: range)
    }

    static func adding(_ trait: UIFontDescriptor.SymbolicTraits, to font: UIFont) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(trait)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    static func headingBoost(_ role: HighlightRole) -> CGFloat {
        switch role {
        case .heading1: 8
        case .heading2: 5
        case .heading3: 3
        case .heading4: 2
        default: 1
        }
    }

    static func nsRange(_ span: HighlightSpan, length: Int) -> NSRange? {
        guard span.startUTF16 >= 0, span.endUTF16 <= length, span.endUTF16 > span.startUTF16 else { return nil }
        return NSRange(location: span.startUTF16, length: span.endUTF16 - span.startUTF16)
    }
}
#endif

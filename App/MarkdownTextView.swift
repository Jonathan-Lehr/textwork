import SwiftUI
import TextworkEditor

private func clampedRange(_ range: Range<Int>, length: Int) -> NSRange? {
    let lower = max(0, range.lowerBound)
    let upper = min(length, range.upperBound)
    guard upper > lower else { return nil }
    return NSRange(location: lower, length: upper - lower)
}

private func clippedRanges(of span: HighlightSpan, limits: [Range<Int>], length: Int) -> [NSRange] {
    var pieces: [NSRange] = []
    for limit in limits {
        let lower = max(0, max(span.startUTF16, limit.lowerBound))
        let upper = min(length, min(span.endUTF16, limit.upperBound))
        guard upper > lower else { continue }
        pieces.append(NSRange(location: lower, length: upper - lower))
    }
    return pieces
}

#if os(macOS)
import AppKit

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var configuration = EditorConfiguration.standard

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, configuration: configuration)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        configuration.apply(to: textView)
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView

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
        context.coordinator.textView = textView
        if context.coordinator.configuration != configuration {
            context.coordinator.configuration = configuration
            configuration.apply(to: textView)
            context.coordinator.repaint(in: textView)
        }
        guard textView.string != text, !context.coordinator.isApplyingHighlight else { return }
        context.coordinator.replaceAll(text, in: textView)
    }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        @Binding var text: String
        let highlighter = MarkdownHighlighter()
        var configuration: EditorConfiguration
        var snapshot: HighlightSnapshot
        var isApplyingHighlight = false
        weak var textView: NSTextView?

        init(text: Binding<String>, configuration: EditorConfiguration) {
            _text = text
            self.configuration = configuration
            snapshot = highlighter.highlight(text.wrappedValue)
        }

        @MainActor
        func repaint(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = 0..<storage.length
            paint(snapshot.spans, ranges: storage.length > 0 ? [full] : [], in: storage, textView: textView)
        }

        @MainActor
        func replaceAll(_ replacement: String, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            isApplyingHighlight = true
            storage.setAttributedString(NSAttributedString(string: replacement))
            snapshot = highlighter.highlight(replacement)
            paint(snapshot.spans, ranges: snapshot.invalidatedUTF16Ranges, in: storage, textView: textView)
            isApplyingHighlight = false
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
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
            paint(snapshot.spans, ranges: snapshot.invalidatedUTF16Ranges, in: textStorage, textView: textView)
            isApplyingHighlight = false
            text = textStorage.string
        }

        private func paint(
            _ spans: [HighlightSpan],
            ranges: [Range<Int>],
            in storage: NSTextStorage,
            textView: NSTextView?
        ) {
            let undoManager = textView?.undoManager
            undoManager?.disableUndoRegistration()
            defer {
                undoManager?.enableUndoRegistration()
                textView?.typingAttributes = configuration.baseAttributes()
            }
            guard !ranges.isEmpty else { return }
            let affected = spans.filter { span in
                ranges.contains { limit in
                    limit.lowerBound < span.endUTF16 && span.startUTF16 < limit.upperBound
                }
            }
            storage.beginEditing()
            for range in ranges {
                guard let nsRange = clampedRange(range, length: storage.length) else { continue }
                storage.setAttributes(configuration.baseAttributes(), range: nsRange)
            }
            for span in affected where !span.isSyntax {
                HighlightColors.applyContent(span, configuration: configuration, to: storage, limits: ranges)
            }
            for span in affected where span.isSyntax {
                HighlightColors.applySyntax(span, configuration: configuration, to: storage, limits: ranges)
            }
            storage.endEditing()
        }
    }
}

private enum HighlightColors {
    static var syntax: NSColor { NSColor.tertiaryLabelColor }
    static var link: NSColor { NSColor.linkColor }
    static var html: NSColor { NSColor.systemTeal }
    static var codeBackground: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.35) }

    static func applyContent(
        _ span: HighlightSpan,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        limits: [Range<Int>]
    ) {
        for range in clippedRanges(of: span, limits: limits, length: storage.length) {
            applyContent(span, configuration: configuration, to: storage, range: range)
        }
    }

    static func applyContent(
        _ span: HighlightSpan,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        var font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? configuration.bodyFont()
        let manager = NSFontManager.shared
        switch span.role {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            let size = configuration.resolvedFontSize + headingBoost(span.role)
            font = manager.convert(configuration.font(ofSize: size), toHaveTrait: .boldFontMask)
        case .emphasis:
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        case .strong:
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        case .codeSpan, .codeBlock:
            font = configuration.monospacedFont()
            storage.addAttribute(.backgroundColor, value: codeBackground, range: range)
        case .link, .image:
            storage.addAttribute(.foregroundColor, value: link, range: range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .html:
            font = configuration.monospacedFont()
            storage.addAttribute(.foregroundColor, value: html, range: range)
        case .table, .listMarker, .blockQuote, .thematicBreak:
            break
        }
        storage.addAttribute(.font, value: font, range: range)
    }

    static func applySyntax(
        _ span: HighlightSpan,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        limits: [Range<Int>]
    ) {
        for range in clippedRanges(of: span, limits: limits, length: storage.length) {
            storage.addAttributes(
                [.font: configuration.bodyFont(), .foregroundColor: syntax],
                range: range
            )
        }
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
}

#else
import UIKit

struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    var configuration = EditorConfiguration.standard

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, configuration: configuration)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        configuration.apply(to: textView)
        textView.textStorage.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.replaceAll(text, in: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.textView = textView
        if context.coordinator.configuration != configuration {
            context.coordinator.configuration = configuration
            configuration.apply(to: textView)
            context.coordinator.repaint(in: textView)
        }
        guard textView.text != text, !context.coordinator.isApplyingHighlight else { return }
        context.coordinator.replaceAll(text, in: textView)
    }

    final class Coordinator: NSObject, NSTextStorageDelegate {
        @Binding var text: String
        let highlighter = MarkdownHighlighter()
        var configuration: EditorConfiguration
        var snapshot: HighlightSnapshot
        var isApplyingHighlight = false
        weak var textView: UITextView?

        init(text: Binding<String>, configuration: EditorConfiguration) {
            _text = text
            self.configuration = configuration
            snapshot = highlighter.highlight(text.wrappedValue)
        }

        @MainActor
        func repaint(in textView: UITextView) {
            let storage = textView.textStorage
            let full = 0..<storage.length
            paint(snapshot.spans, ranges: storage.length > 0 ? [full] : [], in: storage, textView: textView)
        }

        @MainActor
        func replaceAll(_ replacement: String, in textView: UITextView) {
            let storage = textView.textStorage
            isApplyingHighlight = true
            storage.setAttributedString(NSAttributedString(string: replacement))
            snapshot = highlighter.highlight(replacement)
            paint(snapshot.spans, ranges: snapshot.invalidatedUTF16Ranges, in: storage, textView: textView)
            isApplyingHighlight = false
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
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
            paint(snapshot.spans, ranges: snapshot.invalidatedUTF16Ranges, in: textStorage, textView: textView)
            isApplyingHighlight = false
            text = textStorage.string
        }

        private func paint(
            _ spans: [HighlightSpan],
            ranges: [Range<Int>],
            in storage: NSTextStorage,
            textView: UITextView?
        ) {
            let undoManager = textView?.undoManager
            undoManager?.disableUndoRegistration()
            defer {
                undoManager?.enableUndoRegistration()
                textView?.typingAttributes = configuration.baseAttributes()
            }
            guard !ranges.isEmpty else { return }
            let affected = spans.filter { span in
                ranges.contains { limit in
                    limit.lowerBound < span.endUTF16 && span.startUTF16 < limit.upperBound
                }
            }
            storage.beginEditing()
            for range in ranges {
                guard let nsRange = clampedRange(range, length: storage.length) else { continue }
                storage.setAttributes(configuration.baseAttributes(), range: nsRange)
            }
            for span in affected where !span.isSyntax {
                HighlightColors.applyContent(span, configuration: configuration, to: storage, limits: ranges)
            }
            for span in affected where span.isSyntax {
                HighlightColors.applySyntax(span, configuration: configuration, to: storage, limits: ranges)
            }
            storage.endEditing()
        }
    }
}

private enum HighlightColors {
    static var syntax: UIColor { UIColor.tertiaryLabel }
    static var link: UIColor { UIColor.link }
    static var html: UIColor { UIColor.systemTeal }
    static var codeBackground: UIColor { UIColor.tertiarySystemFill }

    static func applyContent(
        _ span: HighlightSpan,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        limits: [Range<Int>]
    ) {
        for range in clippedRanges(of: span, limits: limits, length: storage.length) {
            applyContent(span, configuration: configuration, to: storage, range: range)
        }
    }

    static func applyContent(
        _ span: HighlightSpan,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        var font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont) ?? configuration.bodyFont()
        switch span.role {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            let size = configuration.resolvedFontSize + headingBoost(span.role)
            font = adding(.traitBold, to: configuration.font(ofSize: size))
        case .emphasis:
            font = adding(.traitItalic, to: font)
        case .strong:
            font = adding(.traitBold, to: font)
        case .codeSpan, .codeBlock:
            font = configuration.monospacedFont()
            storage.addAttribute(.backgroundColor, value: codeBackground, range: range)
        case .link, .image:
            storage.addAttribute(.foregroundColor, value: link, range: range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .html:
            font = configuration.monospacedFont()
            storage.addAttribute(.foregroundColor, value: html, range: range)
        case .table, .listMarker, .blockQuote, .thematicBreak:
            break
        }
        storage.addAttribute(.font, value: font, range: range)
    }

    static func applySyntax(
        _ span: HighlightSpan,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        limits: [Range<Int>]
    ) {
        for range in clippedRanges(of: span, limits: limits, length: storage.length) {
            storage.addAttributes(
                [.font: configuration.bodyFont(), .foregroundColor: syntax],
                range: range
            )
        }
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

}
#endif

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

/// `true` when `selection` lies inside a storage of `storageLength`.
/// An empty storage accepts `{0, 0}`.
private func selectionFitsInStorage(_ selection: NSRange, storageLength: Int) -> Bool {
    guard storageLength >= 0, selection.location != NSNotFound else { return false }
    guard selection.location >= 0, selection.length >= 0 else { return false }
    let selectionEnd = selection.location + selection.length
    guard selectionEnd >= selection.location else { return false }
    return selectionEnd <= storageLength
}

private func typingAttributesMatch(
    _ current: [NSAttributedString.Key: Any],
    _ desired: [NSAttributedString.Key: Any]
) -> Bool {
    let keys: [NSAttributedString.Key] = [.font, .foregroundColor, .paragraphStyle]
    for key in keys {
        switch (current[key] as? NSObject, desired[key] as? NSObject) {
        case (nil, nil):
            continue
        case let (currentValue?, desiredValue?):
            if !currentValue.isEqual(desiredValue) { return false }
        default:
            return false
        }
    }
    return true
}

private func rangesInsideStorage(_ ranges: [Range<Int>], length: Int) -> [Range<Int>] {
    guard length > 0 else { return [] }
    return ranges.compactMap { range in
        guard let clamped = clampedRange(range, length: length) else { return nil }
        return clamped.location..<(clamped.location + clamped.length)
    }
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

    @MainActor
    final class Coordinator: NSObject, NSTextStorageDelegate {
        @Binding var text: String
        let highlighter = MarkdownHighlighter()
        var configuration: EditorConfiguration
        var snapshot: HighlightSnapshot
        var isApplyingHighlight = false
        private var isTypingAttributeRestoreScheduled = false
        weak var textView: NSTextView?

        init(text: Binding<String>, configuration: EditorConfiguration) {
            _text = text
            self.configuration = configuration
            snapshot = highlighter.highlight(text.wrappedValue)
        }

        func repaint(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = 0..<storage.length
            paint(snapshot.spans, ranges: storage.length > 0 ? [full] : [], in: storage, textView: textView)
            applyTypingAttributes()
        }

        func replaceAll(_ replacement: String, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            isApplyingHighlight = true
            storage.setAttributedString(NSAttributedString(string: replacement))
            snapshot = highlighter.highlight(replacement)
            paint(snapshot.spans, ranges: snapshot.invalidatedUTF16Ranges, in: storage, textView: textView)
            isApplyingHighlight = false
            applyTypingAttributes()
        }

        /// TextKit calls this on the main thread while the storage is still
        /// inside `processEditing`. The selection can still cover the deleted
        /// characters. Writing `typingAttributes` from here asks the font panel
        /// to read that stale range and raises `NSRangeException` when the
        /// storage is empty.
        nonisolated func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            let storageText = textStorage.string as NSString
            guard editedRange.location != NSNotFound, NSMaxRange(editedRange) <= storageText.length else { return }
            let oldLength = editedRange.length - delta
            guard oldLength >= 0 else { return }
            let oldRange = editedRange.location..<(editedRange.location + oldLength)
            let replacement = storageText.substring(with: editedRange)
            MainActor.assumeIsolated {
                self.finishProcessedEditing(oldRange: oldRange, replacement: replacement)
            }
        }

        private func finishProcessedEditing(oldRange: Range<Int>, replacement: String) {
            guard !isApplyingHighlight, let textView, let storage = textView.textStorage else { return }
            snapshot = highlighter.apply(MarkdownEdit(range: oldRange, replacement: replacement), to: snapshot)
            isApplyingHighlight = true
            paint(snapshot.spans, ranges: snapshot.invalidatedUTF16Ranges, in: storage, textView: textView)
            isApplyingHighlight = false
            scheduleTypingAttributeRestore()
            text = storage.string
        }

        private func paint(
            _ spans: [HighlightSpan],
            ranges: [Range<Int>],
            in storage: NSTextStorage,
            textView: NSTextView?
        ) {
            let undoManager = textView?.undoManager
            undoManager?.disableUndoRegistration()
            defer { undoManager?.enableUndoRegistration() }
            let limits = rangesInsideStorage(ranges, length: storage.length)
            guard !limits.isEmpty else { return }
            let affected = spans.filter { span in
                limits.contains { limit in
                    limit.lowerBound < span.endUTF16 && span.startUTF16 < limit.upperBound
                }
            }
            storage.beginEditing()
            for range in limits {
                guard let nsRange = clampedRange(range, length: storage.length) else { continue }
                storage.setAttributes(configuration.baseAttributes(), range: nsRange)
            }
            for span in affected where !span.isSyntax {
                HighlightColors.apply(span, configuration: configuration, to: storage, limits: limits)
            }
            for span in affected where span.isSyntax {
                HighlightColors.apply(span, configuration: configuration, to: storage, limits: limits)
            }
            storage.endEditing()
        }

        private func scheduleTypingAttributeRestore() {
            guard !isTypingAttributeRestoreScheduled else { return }
            isTypingAttributeRestoreScheduled = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isTypingAttributeRestoreScheduled = false
                self.applyTypingAttributes()
            }
        }

        private func applyTypingAttributes() {
            guard let textView else { return }
            let storageLength = textView.textStorage?.length ?? 0
            guard selectionFitsInStorage(textView.selectedRange(), storageLength: storageLength) else { return }
            let desired = configuration.baseAttributes()
            guard !typingAttributesMatch(textView.typingAttributes, desired) else { return }
            textView.typingAttributes = desired
        }
    }
}

private enum HighlightColors {
    static func apply(
        _ span: HighlightSpan,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        limits: [Range<Int>]
    ) {
        let style = configuration.theme.runStyle(for: span.role, isSyntax: span.isSyntax)
        for range in clippedRanges(of: span, limits: limits, length: storage.length) {
            apply(span, style: style, configuration: configuration, to: storage, range: range)
        }
    }

    static func apply(
        _ span: HighlightSpan,
        style: HighlightRunStyle,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        var font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? configuration.bodyFont()
        let manager = NSFontManager.shared
        switch style.fontTreatment {
        case .body:
            font = configuration.bodyFont()
        case .monospaced:
            font = configuration.monospacedFont()
        case .heading:
            let size = configuration.resolvedFontSize + headingBoost(span.role)
            font = manager.convert(configuration.font(ofSize: size), toHaveTrait: .boldFontMask)
        case .emphasis:
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        case .strong:
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        storage.addAttribute(.font, value: font, range: range)
        storage.addAttribute(.foregroundColor, value: configuration.theme.platformColor(style.foreground), range: range)
        if let background = style.background {
            storage.addAttribute(.backgroundColor, value: configuration.theme.platformColor(background), range: range)
        }
        if style.underline {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
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

    @MainActor
    final class Coordinator: NSObject, NSTextStorageDelegate {
        @Binding var text: String
        let highlighter = MarkdownHighlighter()
        var configuration: EditorConfiguration
        var snapshot: HighlightSnapshot
        var isApplyingHighlight = false
        private var isTypingAttributeRestoreScheduled = false
        weak var textView: UITextView?

        init(text: Binding<String>, configuration: EditorConfiguration) {
            _text = text
            self.configuration = configuration
            snapshot = highlighter.highlight(text.wrappedValue)
        }

        func repaint(in textView: UITextView) {
            let storage = textView.textStorage
            let full = 0..<storage.length
            paint(snapshot.spans, ranges: storage.length > 0 ? [full] : [], in: storage, textView: textView)
            applyTypingAttributes()
        }

        func replaceAll(_ replacement: String, in textView: UITextView) {
            let storage = textView.textStorage
            isApplyingHighlight = true
            storage.setAttributedString(NSAttributedString(string: replacement))
            snapshot = highlighter.highlight(replacement)
            paint(snapshot.spans, ranges: snapshot.invalidatedUTF16Ranges, in: storage, textView: textView)
            isApplyingHighlight = false
            applyTypingAttributes()
        }

        /// TextKit calls this on the main thread while the storage is still
        /// inside `processEditing`. Typing attributes are restored after that
        /// returns, matching the macOS editor. UIKit reads the selection while
        /// applying them, and that selection can still cover the deleted text.
        nonisolated func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            let storageText = textStorage.string as NSString
            guard editedRange.location != NSNotFound, NSMaxRange(editedRange) <= storageText.length else { return }
            let oldLength = editedRange.length - delta
            guard oldLength >= 0 else { return }
            let oldRange = editedRange.location..<(editedRange.location + oldLength)
            let replacement = storageText.substring(with: editedRange)
            MainActor.assumeIsolated {
                self.finishProcessedEditing(oldRange: oldRange, replacement: replacement)
            }
        }

        private func finishProcessedEditing(oldRange: Range<Int>, replacement: String) {
            guard !isApplyingHighlight else { return }
            guard let textView else { return }
            let storage = textView.textStorage
            snapshot = highlighter.apply(MarkdownEdit(range: oldRange, replacement: replacement), to: snapshot)
            isApplyingHighlight = true
            paint(snapshot.spans, ranges: snapshot.invalidatedUTF16Ranges, in: storage, textView: textView)
            isApplyingHighlight = false
            scheduleTypingAttributeRestore()
            text = storage.string
        }

        private func paint(
            _ spans: [HighlightSpan],
            ranges: [Range<Int>],
            in storage: NSTextStorage,
            textView: UITextView?
        ) {
            let undoManager = textView?.undoManager
            undoManager?.disableUndoRegistration()
            defer { undoManager?.enableUndoRegistration() }
            let limits = rangesInsideStorage(ranges, length: storage.length)
            guard !limits.isEmpty else { return }
            let affected = spans.filter { span in
                limits.contains { limit in
                    limit.lowerBound < span.endUTF16 && span.startUTF16 < limit.upperBound
                }
            }
            storage.beginEditing()
            for range in limits {
                guard let nsRange = clampedRange(range, length: storage.length) else { continue }
                storage.setAttributes(configuration.baseAttributes(), range: nsRange)
            }
            for span in affected where !span.isSyntax {
                HighlightColors.apply(span, configuration: configuration, to: storage, limits: limits)
            }
            for span in affected where span.isSyntax {
                HighlightColors.apply(span, configuration: configuration, to: storage, limits: limits)
            }
            storage.endEditing()
        }

        private func scheduleTypingAttributeRestore() {
            guard !isTypingAttributeRestoreScheduled else { return }
            isTypingAttributeRestoreScheduled = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isTypingAttributeRestoreScheduled = false
                self.applyTypingAttributes()
            }
        }

        private func applyTypingAttributes() {
            guard let textView else { return }
            let storageLength = textView.textStorage.length
            guard selectionFitsInStorage(textView.selectedRange, storageLength: storageLength) else { return }
            let desired = configuration.baseAttributes()
            guard !typingAttributesMatch(textView.typingAttributes, desired) else { return }
            textView.typingAttributes = desired
        }
    }
}

private enum HighlightColors {
    static func apply(
        _ span: HighlightSpan,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        limits: [Range<Int>]
    ) {
        let style = configuration.theme.runStyle(for: span.role, isSyntax: span.isSyntax)
        for range in clippedRanges(of: span, limits: limits, length: storage.length) {
            apply(span, style: style, configuration: configuration, to: storage, range: range)
        }
    }

    static func apply(
        _ span: HighlightSpan,
        style: HighlightRunStyle,
        configuration: EditorConfiguration,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        var font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont) ?? configuration.bodyFont()
        switch style.fontTreatment {
        case .body:
            font = configuration.bodyFont()
        case .monospaced:
            font = configuration.monospacedFont()
        case .heading:
            let size = configuration.resolvedFontSize + headingBoost(span.role)
            font = adding(.traitBold, to: configuration.font(ofSize: size))
        case .emphasis:
            font = adding(.traitItalic, to: font)
        case .strong:
            font = adding(.traitBold, to: font)
        }
        storage.addAttribute(.font, value: font, range: range)
        storage.addAttribute(.foregroundColor, value: configuration.theme.platformColor(style.foreground), range: range)
        if let background = style.background {
            storage.addAttribute(.backgroundColor, value: configuration.theme.platformColor(background), range: range)
        }
        if style.underline {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
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

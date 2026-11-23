import AppKit
import SwiftUI
import XCTest

@MainActor
final class EditorDeletionTests: XCTestCase {
    private var documentText = ""

    func testNewDocumentStartsEmpty() {
        XCTAssertEqual(MarkdownDocument().text, "")
        XCTAssertFalse(MarkdownDocument.markdownGuide.isEmpty)
        XCTAssertTrue(MarkdownDocument.markdownGuide.contains("# Textwork"))
        XCTAssertTrue(MarkdownDocument.markdownGuide.contains("inline code"))
    }

    func testDeletingTheSelectionThenTyping() async {
        let harness = makeHarness(text: "# Heading\n\nBody with *emphasis*.")
        defer { harness.close() }
        harness.textView.selectAll(nil)
        var attributes = harness.textView.typingAttributes
        attributes[.font] = NSFont.boldSystemFont(ofSize: 28)
        harness.textView.typingAttributes = attributes
        harness.textView.deleteBackward(nil)
        XCTAssertEqual(harness.textView.string, "")
        XCTAssertEqual(documentText, "")
        await waitForTypingAttributeRestore()
        assertBodyTypingFont(harness.textView, configuration: harness.configuration)
        harness.textView.insertText("Hello", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(harness.textView.string, "Hello")
        XCTAssertEqual(documentText, "Hello")
        assertStoredFontIsBody(harness.textView, configuration: harness.configuration)
    }

    func testDeletingEveryCharacterThenTyping() async {
        let harness = makeHarness(text: "# Heading")
        defer { harness.close() }
        let length = (harness.textView.string as NSString).length
        harness.textView.setSelectedRange(NSRange(location: length, length: 0))
        while !harness.textView.string.isEmpty {
            harness.textView.deleteBackward(nil)
        }
        XCTAssertEqual(harness.textView.string, "")
        XCTAssertEqual(documentText, "")
        await waitForTypingAttributeRestore()
        harness.textView.insertText("Hello", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(harness.textView.string, "Hello")
        XCTAssertEqual(documentText, "Hello")
    }

    func testEmptyDocumentAcceptsTyping() async {
        let harness = makeHarness(text: "")
        defer { harness.close() }
        harness.textView.insertText("Hello", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(harness.textView.string, "Hello")
        XCTAssertEqual(documentText, "Hello")
    }

    private func makeHarness(text: String) -> EditorHarness {
        documentText = text
        let editor = MarkdownTextEditor(text: Binding(get: { self.documentText }, set: { self.documentText = $0 }))
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 800)
        editor.configuration.apply(to: textView)
        textView.textStorage?.delegate = coordinator
        coordinator.textView = textView
        coordinator.replaceAll(text, in: textView)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: scrollView.frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(textView))
        XCTAssertTrue(window.firstResponder === textView)
        return EditorHarness(
            textView: textView,
            window: window,
            coordinator: coordinator,
            configuration: editor.configuration
        )
    }

    private func waitForTypingAttributeRestore() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }

    private func assertBodyTypingFont(_ textView: NSTextView, configuration: EditorConfiguration) {
        let typingFont = textView.typingAttributes[.font] as? NSFont
        XCTAssertTrue(typingFont?.isEqual(configuration.bodyFont()) == true)
    }

    private func assertStoredFontIsBody(_ textView: NSTextView, configuration: EditorConfiguration) {
        let storedFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(storedFont?.pointSize, configuration.bodyFont().pointSize)
    }
}

@MainActor
private final class EditorHarness {
    let textView: NSTextView
    let window: NSWindow
    let coordinator: MarkdownTextEditor.Coordinator
    let configuration: EditorConfiguration

    init(
        textView: NSTextView,
        window: NSWindow,
        coordinator: MarkdownTextEditor.Coordinator,
        configuration: EditorConfiguration
    ) {
        self.textView = textView
        self.window = window
        self.coordinator = coordinator
        self.configuration = configuration
    }

    func close() {
        textView.textStorage?.delegate = nil
        window.close()
    }
}

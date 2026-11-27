import AppKit
import SwiftUI
import XCTest

@MainActor
final class EditorDeletionTests: XCTestCase {
    private var documentText = ""

    override func setUp() async throws {
        try await super.setUp()
        let application = NSApplication.shared
        if application.activationPolicy() != .accessory { application.setActivationPolicy(.accessory) }
        // xctest does not finish launching the application. On the GitHub
        // runner, making a window key before this returns aborts the process.
        if !application.isRunning { application.finishLaunching() }
    }

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
        var remaining = length
        while !harness.textView.string.isEmpty {
            let before = (harness.textView.string as NSString).length
            harness.textView.deleteBackward(nil)
            let after = (harness.textView.string as NSString).length
            XCTAssertLessThan(after, before)
            remaining -= 1
            XCTAssertGreaterThanOrEqual(remaining, 0)
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
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        editor.configuration.apply(to: textView)
        textView.textStorage?.delegate = coordinator
        coordinator.textView = textView

        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: scrollView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        window.orderFrontRegardless()
        XCTAssertTrue(window.makeFirstResponder(textView))
        coordinator.replaceAll(text, in: textView)
        return EditorHarness(
            textView: textView,
            window: window,
            coordinator: coordinator,
            configuration: editor.configuration
        )
    }

    /// The editor restores typing attributes on a later main-actor turn so the
    /// font panel does not read a selection that the delete has not updated yet.
    private func waitForTypingAttributeRestore() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
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
        window.orderOut(nil)
        window.close()
    }
}

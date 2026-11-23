import AppKit
import SwiftUI
import TextworkEditor
import WebKit
import XCTest

@MainActor
final class EditorTypographyTests: XCTestCase {
    private var previewWindows: [NSWindow] = []

    func testStandardUsesMenloAtTheDefaultSize() {
        let configuration = EditorConfiguration.standard
        XCTAssertEqual(configuration.typography.fontName, EditorTypography.menloFontName)
        XCTAssertNil(configuration.typography.fontSize)
        XCTAssertEqual(configuration.typography.lineSpacing, 2)
        XCTAssertEqual(configuration.typography.paragraphSpacing, 0)

        let body = configuration.bodyFont()
        XCTAssertEqual(body.familyName, "Menlo")
        XCTAssertEqual(body.fontName, "Menlo-Regular")
        XCTAssertEqual(body.pointSize, NSFont.systemFontSize)
        XCTAssertEqual(configuration.resolvedFontSize, NSFont.systemFontSize)

        let code = configuration.monospacedFont()
        XCTAssertEqual(code.fontName, "Menlo-Regular")
        XCTAssertEqual(code.pointSize, body.pointSize)

        let heading = configuration.boldFont(ofSize: configuration.resolvedFontSize + 8)
        XCTAssertEqual(heading.fontName, "Menlo-Bold")
        XCTAssertEqual(heading.pointSize, NSFont.systemFontSize + 8)

        let italic = configuration.fontAddingItalic(to: body)
        XCTAssertEqual(italic.fontName, "Menlo-Italic")
        XCTAssertEqual(italic.pointSize, body.pointSize)
        let bold = configuration.fontAddingBold(to: body)
        XCTAssertEqual(bold.fontName, "Menlo-Bold")
        XCTAssertEqual(bold.pointSize, body.pointSize)
        XCTAssertEqual(configuration.fontAddingBold(to: italic).fontName, "Menlo-BoldItalic")
        XCTAssertEqual(configuration.fontAddingItalic(to: bold).fontName, "Menlo-BoldItalic")
        XCTAssertEqual(configuration.paragraphStyle().lineSpacing, 2)
    }

    func testMissingMenloFallsBackToTheSystemMonospacedFont() {
        XCTAssertEqual(
            EditorTypography.fontSource(fontName: EditorTypography.menloFontName, nameIsAvailable: true),
            .named(EditorTypography.menloFontName)
        )
        XCTAssertEqual(
            EditorTypography.fontSource(fontName: EditorTypography.menloFontName, nameIsAvailable: false),
            .systemMonospaced
        )
        XCTAssertEqual(
            EditorTypography.fontSource(fontName: nil, nameIsAvailable: false),
            .system
        )
        XCTAssertEqual(
            EditorTypography.fontSource(fontName: "UnknownFace", nameIsAvailable: false),
            .system
        )

        var configuration = EditorConfiguration.standard
        configuration.typography.fontName = "UnknownFace"
        let body = configuration.font(ofSize: 15)
        XCTAssertEqual(body.fontName, NSFont.systemFont(ofSize: 15).fontName)
        let code = configuration.monospacedFont()
        let systemMonospaced = NSFont.monospacedSystemFont(ofSize: configuration.resolvedFontSize, weight: .regular)
        XCTAssertEqual(code.fontName, systemMonospaced.fontName)
        XCTAssertEqual(code.pointSize, systemMonospaced.pointSize)
    }

    func testPaintedDocumentStaysInMenlo() throws {
        let text = MarkdownDocument.markdownGuide
        var documentText = text
        let editor = MarkdownTextEditor(
            text: Binding(get: { documentText }, set: { documentText = $0 })
        )
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        editor.configuration.apply(to: textView)
        let coordinator = editor.makeCoordinator()
        coordinator.textView = textView
        coordinator.replaceAll(text, in: textView)

        let storage = try XCTUnwrap(textView.textStorage)
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            let font = value as? NSFont
            XCTAssertEqual(font?.familyName, "Menlo", "Font at \(range.location) left the Menlo family")
        }
        storage.enumerateAttribute(.paragraphStyle, in: full, options: []) { value, range, _ in
            let style = value as? NSParagraphStyle
            XCTAssertEqual(style?.lineSpacing, 2, "Line spacing at \(range.location)")
        }

        let body = try font(containing: "plain-text", in: storage, source: text)
        XCTAssertEqual(body.fontName, "Menlo-Regular")
        XCTAssertEqual(body.pointSize, NSFont.systemFontSize)

        let heading = try font(containing: "Textwork", in: storage, source: text)
        XCTAssertEqual(heading.fontName, "Menlo-Bold")
        XCTAssertEqual(heading.pointSize, NSFont.systemFontSize + 8)

        let emphasis = try font(containing: "emphasis", in: storage, source: text)
        XCTAssertEqual(emphasis.fontName, "Menlo-Italic")
        XCTAssertEqual(emphasis.pointSize, body.pointSize)

        let strong = try font(containing: "strong", in: storage, source: text)
        XCTAssertEqual(strong.fontName, "Menlo-Bold")
        XCTAssertEqual(strong.pointSize, body.pointSize)

        let inlineCode = try font(containing: "inline", in: storage, source: text)
        XCTAssertEqual(inlineCode.fontName, "Menlo-Regular")
        XCTAssertEqual(inlineCode.pointSize, body.pointSize)

        let fencedCode = try font(containing: "answer", in: storage, source: text)
        XCTAssertEqual(fencedCode.fontName, "Menlo-Regular")
        XCTAssertEqual(fencedCode.pointSize, body.pointSize)

        let theme = editor.configuration.theme
        let inlineLocation = (text as NSString).range(of: "inline").location
        assertPaintedColor(
            storage.attribute(.foregroundColor, at: inlineLocation, effectiveRange: nil) as? NSColor,
            matches: theme.body,
            "Inline code uses the body text color"
        )
        assertPaintedColor(
            storage.attribute(.backgroundColor, at: inlineLocation, effectiveRange: nil) as? NSColor,
            matches: theme.inlineCodeBackground,
            "Inline code keeps its chip"
        )
        assertPaintedColor(
            storage.attribute(.foregroundColor, at: inlineLocation - 1, effectiveRange: nil) as? NSColor,
            matches: theme.color(for: .codeSpan, isSyntax: true),
            "Inline code markers stay quieter than the words"
        )
        let answerLocation = (text as NSString).range(of: "answer").location
        assertPaintedColor(
            storage.attribute(.foregroundColor, at: answerLocation, effectiveRange: nil) as? NSColor,
            matches: theme.color(for: .codeBlock, isSyntax: false),
            "Fenced code keeps the code color"
        )

        XCTAssertEqual(textView.font?.fontName, "Menlo-Regular")
        XCTAssertEqual(textView.defaultParagraphStyle?.lineSpacing, 2)
    }

    func testPreviewCodeLineHeightIsTheDeclaredLength() async throws {
        let application = NSApplication.shared
        if application.activationPolicy() != .accessory {
            application.setActivationPolicy(.accessory)
        }
        if !application.isRunning {
            application.finishLaunching()
        }
        let metrics = try await previewCodeMetrics(appearance: .aqua)
        defer { closePreviewWindows() }
        let codeLineHeight = try XCTUnwrap(metrics["codeLineHeight"] as? Double)
        let preLineHeight = try XCTUnwrap(metrics["preLineHeight"] as? Double)
        let pitch = try XCTUnwrap(metrics["linePitch"] as? Double)
        XCTAssertEqual(codeLineHeight, 13.372, accuracy: 0.2, "pre code computed line-height")
        XCTAssertEqual(preLineHeight, 13.372, accuracy: 0.2, "pre computed line-height")
        XCTAssertEqual(pitch, 13.372, accuracy: 0.75, "baseline pitch \(metrics)")
    }

    func testWriteTypographySnapshotsWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["TEXTWORK_TYPOGRAPHY_SNAPSHOTS"] else { return }
        let application = NSApplication.shared
        if application.activationPolicy() != .accessory {
            application.setActivationPolicy(.accessory)
        }
        if !application.isRunning {
            application.finishLaunching()
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let editorURL = folder.appendingPathComponent("editor_inline_code.png")
        let previewLightURL = folder.appendingPathComponent("preview_inline_code_light.png")
        let previewDarkURL = folder.appendingPathComponent("preview_inline_code_dark.png")
        try writeEditorImage(to: editorURL)
        try await writePreviewImage(to: previewLightURL, appearance: .aqua)
        try await writePreviewImage(to: previewDarkURL, appearance: .darkAqua)
        for url in [editorURL, previewLightURL, previewDarkURL] {
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 1000, url.lastPathComponent)
        }
    }

    private func font(containing text: String, in storage: NSTextStorage, source: String) throws -> NSFont {
        let range = (source as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound, text)
        let location = range.location == NSNotFound ? 0 : range.location
        return try XCTUnwrap(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont, text)
    }

    private func assertPaintedColor(_ color: NSColor?, matches expected: HighlightColor, _ message: String) {
        var resolved: NSColor?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            resolved = color?.usingColorSpace(.sRGB)
        }
        XCTAssertEqual(resolved?.redComponent ?? -1, CGFloat(expected.light.red) / 255, accuracy: 0.02, message)
        XCTAssertEqual(resolved?.greenComponent ?? -1, CGFloat(expected.light.green) / 255, accuracy: 0.02, message)
        XCTAssertEqual(resolved?.blueComponent ?? -1, CGFloat(expected.light.blue) / 255, accuracy: 0.02, message)
    }

    private var snapshotMarkdown: String {
        """
        # Textwork

        Write with *emphasis*, **strong**, and `inline code`.

        ```swift
        let answer = 42
        ```
        """
    }

    private func writeEditorImage(to url: URL) throws {
        let text = snapshotMarkdown
        let width: CGFloat = 560
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 1400)
        var documentText = text
        let editor = MarkdownTextEditor(
            text: Binding(get: { documentText }, set: { documentText = $0 })
        )
        editor.configuration.apply(to: textView)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isEditable = false
        let coordinator = editor.makeCoordinator()
        coordinator.textView = textView
        coordinator.replaceAll(text, in: textView)

        guard let layoutManager = textView.textLayoutManager else {
            XCTFail("Missing layout manager")
            return
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let used = layoutManager.usageBoundsForTextContainer
        let height = max(320, ceil(used.height) + textView.textContainerInset.height * 2 + 24)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        let window = NSWindow(
            contentRect: textView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        textView.appearance = window.appearance
        window.contentView = textView
        window.orderFrontRegardless()
        textView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer {
            window.orderOut(nil)
            window.close()
        }
        guard let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else {
            XCTFail("No editor bitmap")
            return
        }
        textView.cacheDisplay(in: textView.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    private var codeBlockMarkdown: String {
        """
        # Textwork

        Write with *emphasis*, **strong**, and `inline code`.

        ```swift
        let first = 1
        let second = 2
        let third = 3
        ```
        """
    }

    private func previewCodeMetrics(appearance: NSAppearance.Name) async throws -> [String: Any] {
        let webView = try await loadPreview(markdown: codeBlockMarkdown, appearance: appearance, size: NSSize(width: 780, height: 420))
        let script = """
        const pre = document.querySelector('pre');
        const code = pre.querySelector('code');
        const span = code.querySelector('span');
        function metrics(element) {
          const style = getComputedStyle(element);
          return {
            display: style.display,
            fontSize: style.fontSize,
            lineHeight: style.lineHeight,
            paddingTop: style.paddingTop,
            paddingBottom: style.paddingBottom
          };
        }
        const range = document.createRange();
        range.selectNodeContents(code);
        const rects = Array.from(range.getClientRects()).map(rect => rect.top);
        const pitches = [];
        for (let index = 1; index < rects.length; index += 1) {
          const gap = rects[index] - rects[index - 1];
          if (gap > 1) pitches.push(gap);
        }
        const pitch = pitches.length ? pitches.reduce((sum, value) => sum + value, 0) / pitches.length : 0;
        return {
          pre: metrics(pre),
          code: metrics(code),
          span: metrics(span),
          pitches: pitches,
          pitch: pitch
        };
        """
        let value = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        let payload = try XCTUnwrap(value as? [String: Any])
        let pre = try XCTUnwrap(payload["pre"] as? [String: Any])
        let code = try XCTUnwrap(payload["code"] as? [String: Any])
        let span = try XCTUnwrap(payload["span"] as? [String: Any])
        return [
            "preLineHeight": points(pre["lineHeight"]),
            "preFontSize": points(pre["fontSize"]),
            "preDisplay": pre["display"] ?? "",
            "codeLineHeight": points(code["lineHeight"]),
            "codeFontSize": points(code["fontSize"]),
            "codeDisplay": code["display"] ?? "",
            "spanLineHeight": points(span["lineHeight"]),
            "spanFontSize": points(span["fontSize"]),
            "linePitch": payload["pitch"] as? Double ?? 0,
            "pitches": payload["pitches"] ?? [],
        ]
    }

    private func points(_ value: Any?) -> Double {
        guard let text = value as? String else { return -1 }
        return Double(text.replacingOccurrences(of: "px", with: "")) ?? -1
    }

    private func loadPreview(
        markdown: String,
        appearance: NSAppearance.Name,
        size: NSSize
    ) async throws -> WKWebView {
        let preview = PreviewCard(markdown: markdown)
            .frame(width: size.width, height: size.height)
        let hostingView = NSHostingView(rootView: preview)
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        hostingView.appearance = window.appearance
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        previewWindows.append(window)
        return try await waitForWebView(in: hostingView)
    }

    private func closePreviewWindows() {
        for window in previewWindows {
            window.orderOut(nil)
            window.close()
        }
        previewWindows.removeAll()
    }

    private func writePreviewImage(to url: URL, appearance: NSAppearance.Name) async throws {
        let size = NSSize(width: 780, height: 420)
        let preview = PreviewCard(markdown: codeBlockMarkdown)
            .frame(width: size.width, height: size.height)
        let hostingView = NSHostingView(rootView: preview)
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        hostingView.appearance = window.appearance
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer {
            window.orderOut(nil)
            window.close()
        }

        let webView = try await waitForWebView(in: hostingView)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = true
        let image = try await webView.takeSnapshot(configuration: configuration)
        let data = try XCTUnwrap(pngData(image))
        try data.write(to: url)
    }

    private func waitForWebView(in root: NSView) async throws -> WKWebView {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let webView = findWebView(in: root), webView.isLoading == false, webView.url != nil {
                return webView
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("The preview web view did not finish loading.")
        throw EditorTypographySnapshotError.previewDidNotLoad
    }

    private func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let webView = findWebView(in: subview) {
                return webView
            }
        }
        return nil
    }

    private func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

private enum EditorTypographySnapshotError: Error {
    case previewDidNotLoad
}

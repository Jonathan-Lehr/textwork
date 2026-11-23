import AppKit
import SwiftUI
import WebKit
import XCTest

@MainActor
final class PreviewPaneTests: XCTestCase {
    private let paneSize = NSSize(width: 520, height: 700)

    override func setUp() async throws {
        try await super.setUp()
        let application = NSApplication.shared
        if application.activationPolicy() != .accessory {
            application.setActivationPolicy(.accessory)
        }
        if !application.isRunning {
            application.finishLaunching()
        }
    }

    func testPreviewFillsThePaneAndKeepsContrast() async throws {
        let light = try await showPreview(appearance: .aqua)
        defer { light.close() }
        try await assertWebViewReceivesHits(in: light.hostingView)
        let lightPage = try await snapshotPage(in: light.hostingView)
        assertPageHasLightAndDarkPixels(lightPage)

        let dark = try await showPreview(appearance: .darkAqua)
        defer { dark.close() }
        try await assertWebViewReceivesHits(in: dark.hostingView)
        let darkPage = try await snapshotPage(in: dark.hostingView)
        assertPageHasLightAndDarkPixels(darkPage)
    }

    private func showPreview(appearance: NSAppearance.Name) async throws -> PreviewHarness {
        let preview = PreviewCard(markdown: sampleMarkdown)
            .frame(width: paneSize.width, height: paneSize.height)
        let hostingView = NSHostingView(rootView: preview)
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: paneSize)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: paneSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        hostingView.appearance = window.appearance
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return PreviewHarness(window: window, hostingView: hostingView)
    }

    private func assertWebViewReceivesHits(in hostingView: NSView) async throws {
        let webView = try await waitForWebView(in: hostingView)
        let center = CGPoint(x: hostingView.bounds.midX, y: hostingView.bounds.midY)
        let edge = CGPoint(x: 4, y: hostingView.bounds.midY)
        XCTAssertTrue(view(hostingView.hitTest(center), isInside: webView))
        XCTAssertTrue(view(hostingView.hitTest(edge), isInside: webView))
    }

    private func waitForWebView(in root: NSView) async throws -> WKWebView {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let webView = findWebView(in: root), webView.isLoading == false, webView.url != nil {
                return webView
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("The preview web view did not finish loading.")
        throw PreviewPaneTestError.webViewDidNotLoad
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

    private func view(_ hit: NSView?, isInside webView: WKWebView) -> Bool {
        var current = hit
        while let view = current {
            if view === webView {
                return true
            }
            current = view.superview
        }
        return false
    }

    private func snapshotPage(in hostingView: NSView) async throws -> NSImage {
        let webView = try await waitForWebView(in: hostingView)
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        return try await webView.takeSnapshot(configuration: configuration)
    }

    private func assertPageHasLightAndDarkPixels(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            XCTFail("The preview snapshot has no bitmap.")
            return
        }
        var sawDark = false
        var sawLight = false
        let stepX = max(rep.pixelsWide / 40, 1)
        let stepY = max(rep.pixelsHigh / 40, 1)
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
                if luminance < 0.35 { sawDark = true }
                if luminance > 0.85 { sawLight = true }
            }
        }
        XCTAssertTrue(sawDark)
        XCTAssertTrue(sawLight)
    }

    private var sampleMarkdown: String {
        """
        # Textwork

        A plain-text Markdown editor. The card on the side is a read-only preview.

        Write with *emphasis*, **strong**, and `inline code`.

        - Lists keep their markers
        - [Links](https://example.com) stay in the source

        > Block quotes are still just text.

        ```swift
        let answer = 42
        ```
        """
    }
}

@MainActor
private final class PreviewHarness {
    let window: NSWindow
    let hostingView: NSView

    init(window: NSWindow, hostingView: NSView) {
        self.window = window
        self.hostingView = hostingView
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

private enum PreviewPaneTestError: Error {
    case webViewDidNotLoad
}

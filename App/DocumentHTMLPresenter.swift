import CoreGraphics
import Foundation
import TextworkEditor

#if os(macOS)
import AppKit
import PDFKit
import WebKit

/// Loads export HTML and turns it into a paginated PDF or a print job.
///
/// The window stays off screen. WebKit still lays the page out there.
@MainActor
final class DocumentHTMLPresenter: NSObject, WKNavigationDelegate {
    nonisolated static let paginationSlop: CGFloat = 1

    private var webView: WKWebView?
    private var window: NSWindow?
    private var loadContinuation: CheckedContinuation<Void, Error>?

    func pdfDocumentData(html: String, baseURL: URL?, colorScheme: MarkdownHTMLColorScheme) async throws -> Data {
        try await load(html: html, baseURL: baseURL, colorScheme: colorScheme)
        defer { teardown() }
        return try await paginatedPDFData()
    }

    func printDocument(html: String, baseURL: URL?, colorScheme: MarkdownHTMLColorScheme) async throws {
        try await load(html: html, baseURL: baseURL, colorScheme: colorScheme)
        defer { teardown() }
        guard let webView else { return }
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    nonisolated static func pageCount(documentHeight: CGFloat, pageHeight: CGFloat) -> Int {
        guard documentHeight > 0, pageHeight > 0 else { return 1 }
        let fullPages = Int(documentHeight / pageHeight)
        let remainder = documentHeight - CGFloat(fullPages) * pageHeight
        if remainder > paginationSlop { return fullPages + 1 }
        return max(fullPages, 1)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoad(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoad(.failure(error))
    }

    private func load(html: String, baseURL: URL?, colorScheme: MarkdownHTMLColorScheme) async throws {
        let pageSize = NSPrintInfo.shared.paperSize
        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: pageSize),
            configuration: WKWebViewConfiguration()
        )
        webView.navigationDelegate = self
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        apply(colorScheme, to: window, webView: webView)
        window.contentView = webView
        window.alphaValue = 0
        window.orderFrontRegardless()
        self.webView = webView
        self.window = window
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private func paginatedPDFData() async throws -> Data {
        guard let webView else { throw CocoaError(.fileWriteUnknown) }
        let pageSize = NSPrintInfo.shared.paperSize
        let documentHeight = try await contentHeight(in: webView)
        let pageCount = Self.pageCount(documentHeight: documentHeight, pageHeight: pageSize.height)
        webView.frame.size = CGSize(width: pageSize.width, height: CGFloat(pageCount) * pageSize.height)
        window?.setContentSize(webView.frame.size)
        webView.layoutSubtreeIfNeeded()
        let document = PDFDocument()
        for index in 0..<pageCount {
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(
                x: 0,
                y: CGFloat(index) * pageSize.height,
                width: pageSize.width,
                height: pageSize.height
            )
            configuration.allowTransparentBackground = false
            let data = try await webView.pdf(configuration: configuration)
            guard let pageDocument = PDFDocument(data: data), let page = pageDocument.page(at: 0) else { continue }
            document.insert(page, at: document.pageCount)
        }
        guard document.pageCount > 0, let data = document.dataRepresentation() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private func contentHeight(in webView: WKWebView) async throws -> CGFloat {
        let value = try await webView.callAsyncJavaScript(
            "return Math.max(document.body ? document.body.scrollHeight : 0, document.documentElement.scrollHeight)",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        if let number = value as? Double { return CGFloat(number) }
        if let number = value as? Int { return CGFloat(number) }
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        return NSPrintInfo.shared.paperSize.height
    }

    private func apply(_ colorScheme: MarkdownHTMLColorScheme, to window: NSWindow, webView: WKWebView) {
        let appearance: NSAppearance? = switch colorScheme {
        case .dark: NSAppearance(named: .darkAqua)
        case .light, .automatic: NSAppearance(named: .aqua)
        }
        window.appearance = appearance
        webView.appearance = appearance
        var background = NSColor.textBackgroundColor
        appearance?.performAsCurrentDrawingAppearance {
            background = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? NSColor.textBackgroundColor
        }
        webView.underPageBackgroundColor = background
    }

    private func finishLoad(_ result: Result<Void, Error>) {
        loadContinuation?.resume(with: result)
        loadContinuation = nil
    }

    private func teardown() {
        webView?.navigationDelegate = nil
        window?.orderOut(nil)
        window?.close()
        webView = nil
        window = nil
    }
}
#endif

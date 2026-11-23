import SwiftUI
import TextworkEditor
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Read-only HTML preview. The web view is not a text editor.
struct MarkdownPreviewWebView: View {
    var bodyHTML: String
    var resourceDirectory: URL?

    var body: some View {
        MarkdownPreviewRepresentable(bodyHTML: bodyHTML, resourceDirectory: resourceDirectory)
    }
}

#if os(macOS)
private struct MarkdownPreviewRepresentable: NSViewRepresentable {
    var bodyHTML: String
    var resourceDirectory: URL?

    func makeCoordinator() -> MarkdownPreviewCoordinator {
        MarkdownPreviewCoordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(bodyHTML: bodyHTML, resourceDirectory: resourceDirectory, webView: webView)
    }
}
#else
private struct MarkdownPreviewRepresentable: UIViewRepresentable {
    var bodyHTML: String
    var resourceDirectory: URL?

    func makeCoordinator() -> MarkdownPreviewCoordinator {
        MarkdownPreviewCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(bodyHTML: bodyHTML, resourceDirectory: resourceDirectory, webView: webView)
    }
}
#endif

@MainActor
final class MarkdownPreviewCoordinator: NSObject, WKNavigationDelegate {
    let handler = PreviewResourceHandler()
    private let renderer = MarkdownHTMLRenderer(imageAddressing: .preview)
    private var didLoad = false
    private var shellReady = false
    private var loadedBody: String?
    private var pendingBody: String?
    private var loadedDirectory: String?
    private var generation = 0

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // The page itself has no scripts. JavaScript stays on so this app can
        // replace the article and put the scroll offset back without loading
        // the document again. The content security policy refuses page scripts,
        // and the renderer escapes markup.
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(handler, forURLScheme: MarkdownHTMLRenderer.previewScheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        #if os(macOS)
        webView.allowsMagnification = false
        webView.underPageBackgroundColor = PreviewSurface.underPageBackgroundColor
        webView.setAccessibilityLabel("Markdown preview")
        #else
        let pageColor = PreviewSurface.underPageBackgroundColor
        webView.isOpaque = PreviewSurface.usesGlassFrame
        webView.backgroundColor = pageColor
        webView.scrollView.backgroundColor = pageColor
        if PreviewSurface.usesGlassFrame {
            webView.underPageBackgroundColor = pageColor
        }
        webView.accessibilityLabel = "Markdown preview"
        #endif
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    func update(bodyHTML: String, resourceDirectory: URL?, webView: WKWebView) {
        handler.setResourceDirectory(resourceDirectory)
        let directoryKey = resourceDirectory?.standardizedFileURL.path
        if !didLoad || directoryKey != loadedDirectory {
            loadedDirectory = directoryKey
            didLoad = true
            load(bodyHTML, in: webView)
            return
        }
        guard bodyHTML != loadedBody else { return }
        pendingBody = bodyHTML
        applyIfReady(in: webView)
    }

    private func load(_ bodyHTML: String, in webView: WKWebView) {
        shellReady = false
        pendingBody = bodyHTML
        loadedBody = bodyHTML
        handler.setDocumentHTML(
            renderer.document(wrapping: bodyHTML, title: "Preview", surface: PreviewSurface.pageSurface)
        )
        webView.load(URLRequest(url: PreviewResourceHandler.pageURL))
    }

    private func applyIfReady(in webView: WKWebView) {
        guard shellReady, let body = pendingBody, body != loadedBody else { return }
        generation += 1
        let token = generation
        let script = """
        if (window.textworkPreviewGeneration > generation) { return false; }
        window.textworkPreviewGeneration = generation;
        const content = document.getElementById('content');
        if (!content) { return false; }
        const scrolling = document.scrollingElement || document.documentElement;
        const y = scrolling ? scrolling.scrollTop : 0;
        content.innerHTML = body;
        if (scrolling) { scrolling.scrollTop = y; }
        return true;
        """
        Task { @MainActor in
            do {
                let result = try await webView.callAsyncJavaScript(
                    script,
                    arguments: ["body": body, "generation": token],
                    in: nil,
                    contentWorld: .page
                )
                guard token == self.generation, (result as? Bool) != false else { return }
                self.loadedBody = body
            } catch {
                guard token == self.generation else { return }
                self.load(body, in: webView)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        shellReady = true
        applyIfReady(in: webView)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if navigationAction.navigationType == .linkActivated {
            if let external = externalURL(for: url) {
                openExternally(external)
            }
            return .cancel
        }
        if url.scheme?.lowercased() == MarkdownHTMLRenderer.previewScheme {
            return .allow
        }
        return .cancel
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, let external = externalURL(for: url) {
            openExternally(external)
        }
        return nil
    }

    private func externalURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "https" || scheme == "mailto" {
            return url
        }
        guard scheme == MarkdownHTMLRenderer.previewScheme else { return nil }
        if url.path == "/preview.html" || url.path.isEmpty { return nil }
        guard let directory = handler.resourceDirectory else { return nil }
        return MarkdownHTMLRenderer.fileURL(forPreviewPath: url.path, in: directory)
    }

    private func openExternally(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

final class PreviewResourceHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    static let pageURL: URL = {
        let string = "\(MarkdownHTMLRenderer.previewScheme)://\(MarkdownHTMLRenderer.previewHost)/preview.html"
        guard let url = URL(string: string) else {
            preconditionFailure("The preview page URL is valid.")
        }
        return url
    }()

    private let lock = NSLock()
    private var documentHTML = ""
    private var directory: URL?
    private var accessingSecurityScope = false
    private var stoppedIdentifiers: Set<ObjectIdentifier> = []

    func setDocumentHTML(_ html: String) {
        lock.lock()
        documentHTML = html
        lock.unlock()
    }

    func setResourceDirectory(_ url: URL?) {
        lock.lock()
        let same = directory?.standardizedFileURL.path == url?.standardizedFileURL.path
        lock.unlock()
        if same { return }
        let started = url?.startAccessingSecurityScopedResource() ?? false
        lock.lock()
        let previous = directory
        let wasAccessing = accessingSecurityScope
        directory = url
        accessingSecurityScope = started
        lock.unlock()
        if wasAccessing {
            previous?.stopAccessingSecurityScopedResource()
        }
    }

    var resourceDirectory: URL? {
        lock.lock()
        let value = directory
        lock.unlock()
        return value
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, URLError(.badURL))
            return
        }
        if url.path == "/preview.html" {
            let html = copyDocumentHTML()
            let policy = MarkdownHTMLRenderer(imageAddressing: .preview).contentSecurityPolicy
            finish(
                urlSchemeTask,
                data: Data(html.utf8),
                mimeType: "text/html",
                url: url,
                contentSecurityPolicy: policy
            )
            return
        }
        guard let directory = resourceDirectory else {
            fail(urlSchemeTask, URLError(.fileDoesNotExist))
            return
        }
        guard let fileURL = MarkdownHTMLRenderer.fileURL(forPreviewPath: url.path, in: directory) else {
            fail(urlSchemeTask, URLError(.fileDoesNotExist))
            return
        }
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true, let data = try? Data(contentsOf: fileURL) else {
            fail(urlSchemeTask, URLError(.fileDoesNotExist))
            return
        }
        finish(urlSchemeTask, data: data, mimeType: mimeType(for: fileURL), url: url, contentSecurityPolicy: nil)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        stoppedIdentifiers.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }

    private func copyDocumentHTML() -> String {
        lock.lock()
        let html = documentHTML
        lock.unlock()
        return html
    }

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        let identifier = ObjectIdentifier(task)
        lock.lock()
        let stopped = stoppedIdentifiers.contains(identifier)
        if stopped {
            stoppedIdentifiers.remove(identifier)
        }
        lock.unlock()
        return stopped
    }

    private func finish(
        _ task: WKURLSchemeTask,
        data: Data,
        mimeType: String,
        url: URL,
        contentSecurityPolicy: String?
    ) {
        guard !isStopped(task) else { return }
        var headers = [
            "Content-Type": mimeType == "text/html" ? "text/html; charset=utf-8" : mimeType,
            "Cache-Control": "no-store",
        ]
        if let contentSecurityPolicy {
            headers["Content-Security-Policy"] = contentSecurityPolicy
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            fail(task, URLError(.badServerResponse))
            return
        }
        guard !isStopped(task) else { return }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, _ error: Error) {
        guard !isStopped(task) else { return }
        task.didFailWithError(error)
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "bmp":
            return "image/bmp"
        case "heic":
            return "image/heic"
        case "tif", "tiff":
            return "image/tiff"
        default:
            return "application/octet-stream"
        }
    }
}

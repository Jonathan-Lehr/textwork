import SwiftUI
import TextworkEditor

/// Read-only rendered Markdown. This view is not a text editor.
///
/// The preview fills its pane. It has no card fill, border, or inset.
struct PreviewCard: View {
    var markdown: String
    var resourceDirectory: URL?

    @State private var renderedBody: String
    @State private var renderTask: Task<Void, Never>?

    init(markdown: String, resourceDirectory: URL? = nil) {
        self.markdown = markdown
        self.resourceDirectory = resourceDirectory
        _renderedBody = State(
            initialValue: MarkdownHTMLRenderer(imageAddressing: .preview).renderBody(markdown)
        )
    }

    var body: some View {
        MarkdownPreviewWebView(bodyHTML: renderedBody, resourceDirectory: resourceDirectory)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Markdown preview")
            .onChange(of: markdown) { _, newValue in
                scheduleRender(of: newValue)
            }
    }

    private func scheduleRender(of markdown: String) {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) {
                MarkdownHTMLRenderer(imageAddressing: .preview).renderBody(markdown)
            }.value
            guard !Task.isCancelled else { return }
            renderedBody = rendered
        }
    }
}

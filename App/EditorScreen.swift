import SwiftUI

struct EditorScreen: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?

    private var resourceDirectory: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var body: some View {
        #if os(macOS)
        EditorPreviewSplitView(
            editor: editor,
            preview: PreviewCard(markdown: document.text, resourceDirectory: resourceDirectory)
        )
        #else
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                HStack(spacing: 0) {
                    editor
                        .frame(minWidth: 320)
                    PreviewCard(markdown: document.text, resourceDirectory: resourceDirectory)
                        .frame(minWidth: 280, idealWidth: geometry.size.width * 0.42, maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    editor
                    PreviewCard(markdown: document.text, resourceDirectory: resourceDirectory)
                        .frame(height: geometry.size.height * 0.4)
                }
            }
        }
        #endif
    }

    private var editor: some View {
        MarkdownTextEditor(text: $document.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

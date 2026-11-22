import SwiftUI

struct EditorScreen: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?

    private var resourceDirectory: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var body: some View {
        #if os(macOS)
        HSplitView {
            editor
            PreviewCard(markdown: document.text, resourceDirectory: resourceDirectory)
                .frame(minWidth: 280, idealWidth: 380, maxWidth: 560)
        }
        #else
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                HStack(spacing: 0) {
                    editor
                    PreviewCard(markdown: document.text, resourceDirectory: resourceDirectory)
                        .frame(width: min(420, geometry.size.width * 0.42))
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

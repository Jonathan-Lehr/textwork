import SwiftUI

#if os(macOS)
/// Opens the sample document from the Help menu as an untitled document.
struct MarkdownGuideCommands: Commands {
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Markdown Guide") {
                newDocument(MarkdownDocument(text: MarkdownDocument.markdownGuide))
            }
        }
    }
}
#endif

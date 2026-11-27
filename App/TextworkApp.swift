import SwiftUI

@main
struct TextworkApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorScreen(document: file.$document, fileURL: file.fileURL)
        }
        #if os(macOS)
        .commands {
            MarkdownGuideCommands()
            DocumentExportCommands()
        }
        #endif
        #if os(macOS)
        Settings {
            AppearanceSettingsPane()
        }
        #endif
    }
}

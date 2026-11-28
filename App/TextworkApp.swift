import SwiftUI

#if os(macOS)
@MainActor
final class TextworkApplicationDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        SpellingMenu.start()
    }
}
#endif

@main
struct TextworkApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(TextworkApplicationDelegate.self) private var applicationDelegate
    #endif

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

import SwiftUI

@main
struct TextworkApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorScreen(document: file.$document, fileURL: file.fileURL)
        }
    }
}

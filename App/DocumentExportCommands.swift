import SwiftUI
import TextworkEditor
import UniformTypeIdentifiers

#if os(macOS)
import AppKit

struct DocumentExportSource: Equatable {
    var markdown: String
    var fileURL: URL?
    var title: String

    init(markdown: String, fileURL: URL?) {
        self.markdown = markdown
        self.fileURL = fileURL
        if let base = fileURL?.deletingPathExtension().lastPathComponent, !base.isEmpty {
            self.title = base
        } else {
            self.title = "Untitled"
        }
    }

    var resourceDirectory: URL? {
        fileURL?.deletingLastPathComponent()
    }

    func suggestedFileName(pathExtension: String) -> String {
        "\(title).\(pathExtension)"
    }
}

struct DocumentExportSourceKey: FocusedValueKey {
    typealias Value = DocumentExportSource
}

extension FocusedValues {
    var documentExportSource: DocumentExportSource? {
        get { self[DocumentExportSourceKey.self] }
        set { self[DocumentExportSourceKey.self] = newValue }
    }
}

struct DocumentExportCommands: Commands {
    @FocusedValue(\.documentExportSource) private var source

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Export as PDF…") { exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(source == nil)
            Button("Export as HTML…") { exportHTML() }
                .keyboardShortcut("e", modifiers: [.command, .shift, .option])
                .disabled(source == nil)
            Button("Print…") { printDocument() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(source == nil)
        }
    }

    private func exportHTML() {
        guard let source else { return }
        let colorScheme = exportColorScheme(concrete: false)
        guard let url = ExportSavePanel.chooseDestination(
            title: "Export as HTML",
            suggestedName: source.suggestedFileName(pathExtension: "html"),
            contentType: .html
        ) else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let html = MarkdownHTMLRenderer().renderDocument(
                source.markdown,
                title: source.title,
                colorScheme: colorScheme
            )
            try Data(html.utf8).write(to: url, options: .atomic)
        } catch {
            NSApp.presentError(error as NSError)
        }
    }

    private func exportPDF() {
        guard let source else { return }
        let colorScheme = exportColorScheme(concrete: true)
        guard let url = ExportSavePanel.chooseDestination(
            title: "Export as PDF",
            suggestedName: source.suggestedFileName(pathExtension: "pdf"),
            contentType: .pdf
        ) else { return }
        let html = MarkdownHTMLRenderer().renderDocument(
            source.markdown,
            title: source.title,
            colorScheme: colorScheme
        )
        let baseURL = source.resourceDirectory
        let accessing = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try await DocumentHTMLPresenter().pdfDocumentData(
                    html: html,
                    baseURL: baseURL,
                    colorScheme: colorScheme
                )
                try data.write(to: url, options: .atomic)
            } catch {
                NSApp.presentError(error as NSError)
            }
        }
    }

    private func printDocument() {
        guard let source else { return }
        let colorScheme = exportColorScheme(concrete: true)
        let html = MarkdownHTMLRenderer().renderDocument(
            source.markdown,
            title: source.title,
            colorScheme: colorScheme
        )
        let baseURL = source.resourceDirectory
        Task { @MainActor in
            do {
                try await DocumentHTMLPresenter().printDocument(
                    html: html,
                    baseURL: baseURL,
                    colorScheme: colorScheme
                )
            } catch {
                NSApp.presentError(error as NSError)
            }
        }
    }

    private func exportColorScheme(concrete: Bool) -> MarkdownHTMLColorScheme {
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return ExportAppearance.stored().htmlColorScheme(
            applicationAppearance: AppearancePreference.stored(),
            systemIsDark: systemIsDark,
            concrete: concrete
        )
    }
}

private enum ExportSavePanel {
    @MainActor
    static func chooseDestination(title: String, suggestedName: String, contentType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = "Export"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
#endif

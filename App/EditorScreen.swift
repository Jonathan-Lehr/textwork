import SwiftUI

struct EditorScreen: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?
    #if os(iOS)
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.automatic
    @State private var showsAppearanceSettings = false
    #endif

    private var resourceDirectory: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var body: some View {
        #if os(macOS)
        EditorPreviewSplitView(
            editor: editor,
            preview: PreviewCard(markdown: document.text, resourceDirectory: resourceDirectory)
        )
        .onAppear {
            AppearancePreference.stored().applyToApplication()
            SpellingMenu.start()
        }
        .focusedSceneValue(
            \.documentExportSource,
            DocumentExportSource(markdown: document.text, fileURL: fileURL)
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
        .preferredColorScheme(appearance.colorScheme)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsAppearanceSettings = true
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
            }
        }
        .sheet(isPresented: $showsAppearanceSettings) {
            NavigationStack {
                AppearanceSettingsPane()
                    .navigationTitle("Appearance")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsAppearanceSettings = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        #endif
    }

    private var editor: some View {
        MarkdownTextEditor(text: $document.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

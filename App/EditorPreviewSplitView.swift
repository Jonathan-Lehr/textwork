import SwiftUI

#if os(macOS)
import AppKit

private let editorPreviewAutosaveName = "TextworkEditorPreviewSplit"
private let editorPaneMinimum: CGFloat = 320
private let previewPaneMinimum: CGFloat = 280

/// Vertical split between the editor and the preview.
///
/// SwiftUI `HSplitView` was not giving a divider that could be dragged once the
/// panes were AppKit text and web views. This is the system split view, with a
/// minimum width on each side and no maximum, so both panes grow with the window.
struct EditorPreviewSplitView<Editor: View, Preview: View>: NSViewRepresentable {
    var editor: Editor
    var preview: Preview

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = editorPreviewAutosaveName
        splitView.delegate = context.coordinator

        let editorHost = NSHostingView(rootView: editor)
        let previewHost = NSHostingView(rootView: preview)
        editorHost.sizingOptions = []
        previewHost.sizingOptions = []
        splitView.addArrangedSubview(editorHost)
        splitView.addArrangedSubview(previewHost)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        context.coordinator.editorHost = editorHost
        context.coordinator.previewHost = previewHost
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.editorHost?.rootView = editor
        context.coordinator.previewHost?.rootView = preview
        context.coordinator.applyInitialPositionIfNeeded(splitView)
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        var editorHost: NSHostingView<Editor>?
        var previewHost: NSHostingView<Preview>?
        private var didApplyInitialPosition = false

        func applyInitialPositionIfNeeded(_ splitView: NSSplitView) {
            guard !didApplyInitialPosition else { return }
            let width = splitView.bounds.width
            guard width > editorPaneMinimum + previewPaneMinimum else { return }
            didApplyInitialPosition = true
            let savedKey = "NSSplitView Subview Frames \(editorPreviewAutosaveName)"
            if UserDefaults.standard.object(forKey: savedKey) != nil {
                return
            }
            let previewWidth = max(previewPaneMinimum, width * 0.4)
            let editorWidth = width - previewWidth - splitView.dividerThickness
            splitView.setPosition(max(editorWidth, editorPaneMinimum), ofDividerAt: 0)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            editorPaneMinimum
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            max(editorPaneMinimum, splitView.bounds.width - previewPaneMinimum - splitView.dividerThickness)
        }

        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            false
        }
    }
}
#endif

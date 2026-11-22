import SwiftUI

/// Read-only rendered Markdown. This view is not a text editor.
struct PreviewCard: View {
    let markdown: String

    var body: some View {
        ScrollView {
            Text(rendered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
                .textSelection(.enabled)
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1)
        )
        .padding(16)
        .accessibilityLabel("Markdown preview")
        .accessibilityAddTraits(.isStaticText)
    }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: markdown, options: options) {
            return parsed
        }
        return AttributedString(markdown)
    }
}

# Agent notes for Textwork

Textwork is a native Markdown editor. macOS is the primary design target, then iPad. iPhone is last.

## Goals

- Simplicity, clarity, and modularity, with an emphasis on human readability and maintainability
- Correctness
- Security
- Reusability

## Product rules

- The interface is native SwiftUI. Where SwiftUI cannot do the job, wrap TextKit 2 (`NSTextView` on Mac, `UITextView` on iPad and iPhone). Do not add a custom editor toolkit.
- Documents are plain `.md` files. Do not invent a bundle, database, or rich-text storage format.
- The live preview is read-only. It is visually distinct from the editor (inset card, border, wider margins) and it is never an editable text view.
- Ship standard Mac shortcuts and menu commands. Do not add a custom keybinding UI yet.
- Prefer Apple frameworks. A third-party dependency is allowed only with a written decision record in `docs/decisions/` that says why an Apple API is not enough.
- Parser and highlighter code lives in `Packages/TextworkEditor` and has unit tests.

## Names

Spell names out. Do not abbreviate type names, function names, or enum cases. Write `punctuation`, not `punct`. Widely used standard names are fine: UTF-16, URL, HTML, PDF, and Markdown syntax names that readers already know.

## Style

- Indent with four spaces. Do not use tab characters.
- Prefer a one-line `case` when the case body is a single short statement. A case with more than one statement stays on multiple lines:

```swift
switch style.fontTreatment {
case .body: font = configuration.bodyFont()
case .monospaced: font = configuration.monospacedFont()
case .boldMonospaced: font = configuration.boldFont(ofSize: configuration.resolvedFontSize)
case .heading:
    let size = configuration.resolvedFontSize + headingBoost(span.role)
    font = configuration.boldFont(ofSize: size)
case .emphasis: font = configuration.fontAddingItalic(to: font)
case .strong: font = configuration.fontAddingBold(to: font)
}
```

## Layout

- `App/` is the SwiftUI document app.
- `Packages/TextworkEditor` is the editor library, the swift-markdown comparison target, the tests, and the benchmark executable.
- `docs/decisions/` holds architecture decision records.
- `docs/spikes/highlighting.md` is the syntax-highlighting spike.
- `.github/workflows/macos.yml` builds and tests on every push and pull request.
- `.github/workflows/ios.yml` builds the iOS Simulator app weekly and on manual dispatch.

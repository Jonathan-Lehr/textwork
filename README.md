# Textwork

Textwork is a native, open-source Markdown editor. macOS comes first, then iPad. iPhone is a distant last. It is meant to ship on the App Store.

The license is MIT. See [LICENSE](LICENSE).

This repository is the project skeleton plus a syntax-highlighting spike. The product plan is in [ROADMAP.md](ROADMAP.md). Rules for changing the code, including the quality goals and the Swift style, are in [AGENTS.md](AGENTS.md).

## Requirements

- macOS 14 or later for the app, iOS 17 or later for the iPad build
- Xcode 26.6, which is what continuous integration uses
- Swift 6.2

## Layout

| Path | What it is |
| --- | --- |
| `App/` | SwiftUI document app |
| `Packages/TextworkEditor` | Highlighter, HTML renderer, tests, and benchmark |
| `docs/decisions/` | Architecture decision records |
| `docs/spikes/highlighting.md` | Highlighting spike write-up |
| `Config/Textwork.entitlements` | iCloud Drive entitlements, not yet attached to the target |

## Build and test

Tests and the benchmark do not need the app:

```sh
swift test --package-path Packages/TextworkEditor
swift run -c release --package-path Packages/TextworkEditor TextworkEditorBench
```

The Mac app:

```sh
xcodebuild -project Textwork.xcodeproj -scheme Textwork -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

The iOS Simulator build (iPhone and iPad, deployment target iOS 17):

```sh
xcodebuild -project Textwork.xcodeproj -scheme Textwork -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions runs the Mac build, tests, and release benchmark on every push and pull request. The iOS workflow runs on Monday and when someone starts it by hand.

## iCloud Drive

The app is document-based (`DocumentGroup`), which is the AppKit and UIKit path for iCloud Drive. `Config/Textwork.entitlements` names the container `iCloud.com.jonathanlehr.Textwork`. It is not attached to the target yet, because that entitlement needs a paid team and a provisioned App ID. Attach it with `CODE_SIGN_ENTITLEMENTS` when the App ID exists. Continuous integration builds with code signing turned off.

## Highlighting

The editor highlights raw Markdown with a hand-rolled incremental line and block highlighter in `TextworkEditor`. The read-only preview renders HTML from `MarkdownHTMLRenderer` in the same package, inside a web view that is not editable. The comparison with swift-markdown, and why tree-sitter was not measured, is in [docs/spikes/highlighting.md](docs/spikes/highlighting.md). The preview decision is [ADR 0005](docs/decisions/0005-html-preview.md).

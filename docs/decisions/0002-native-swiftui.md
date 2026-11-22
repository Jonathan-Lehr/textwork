# ADR 0002: Native SwiftUI, Mac first

- Status: Accepted
- Date: 2026-11-22

## Context

Textwork is a Mac app first, an iPad app second, and an iPhone app last. It should feel like a system app and ship through the App Store. A cross-platform UI toolkit would fight AppKit and UIKit document support, text, printing, and iCloud Drive.

SwiftUI does not yet cover every text-editing need. Syntax highlighting of a large buffer needs TextKit 2.

## Decision

Build a SwiftUI multiplatform app. The deployment targets are macOS 14 and iOS 17. The shared target includes iPhone so the project builds, but layout and features are designed for the Mac, then for a regular-width iPad.

Where SwiftUI has no text view that can show live highlighting, wrap TextKit 2: `NSTextView(usingTextLayoutManager: true)` on Mac and `UITextView(usingTextLayoutManager: true)` on iOS. Do not call `layoutManager`, which switches the view back to TextKit 1.

Use `DocumentGroup` so the file is a system document. That is also the path to iCloud Drive. The iCloud entitlement file is in the repository and stays unattached until an App ID exists.

Prefer Apple frameworks. Any third-party dependency needs its own decision record.

## Consequences

One Xcode target builds Mac and iPad. The editor engine stays in a Swift package so tests do not need a window. We do not get a custom keybinding UI, a web view, or a third-party text component. Printing and PDF later go through the system print path rather than a PDF library.

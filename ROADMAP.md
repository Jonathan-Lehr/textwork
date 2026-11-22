# Roadmap

macOS is the design target for every phase. iPad follows the same document model. iPhone is not a design target yet.

## Phase 1 — Single-file editor (MVP)

A better TextEdit for one Markdown file.

- Open and save plain `.md` files in a document-based SwiftUI app, including iCloud Drive once the App ID has an iCloud container.
- Edit raw Markdown with live syntax highlighting.
- Read-only preview that does not look like the editor and cannot be edited.
- Export HTML, and PDF through the system print sheet.
- Typography preferences: font, size, line spacing, paragraph spacing.
- Links and images. Image paths are relative to the file.
- Standard Mac menus and shortcuts. No custom keybinding screen.

The highlighting spike in `docs/spikes/highlighting.md` is the first slice of this phase: the editor package, tests, benchmark, and a minimal Mac window.

## Phase 2 — Project folder and compile

A streamlined Scrivener-like tool.

- A project is a folder of `.md` files.
- Sections can be reordered by dragging.
- Compile the project to PDF and HTML.

## Later — editing modes 2 and 3

Not part of the MVP.

- Mode 2 dims Markdown syntax characters.
- Mode 3 hides syntax except near the cursor.

The highlighter already marks syntax spans separately from content so these modes do not require a second parser. There is no custom keybinding UI in either mode.

# ADR 0004: Hand-rolled incremental highlighting

- Status: Accepted
- Date: 2026-11-22

## Context

The editor shows raw Markdown while the user types. Highlighting has to cover CommonMark and GitHub-flavored constructs used in the MVP: headings, emphasis, code spans, fenced code, links, images, lists, block quotes, and tables. It has to stay responsive for a 10 KB note, a 100 KB chapter, and a 1 MB manuscript. Later editing modes dim syntax characters (mode 2) or hide them except near the cursor (mode 3), so the highlighter must know which ranges are punctuation and which are content.

The spike compared four approaches. Measurements and the rejects are in `docs/spikes/highlighting.md`.

## Decision

The app links `TextworkEditor` and nothing else. That library highlights with a hand-rolled line and block scan plus an inline scan. A keystroke reparses only the blocks whose bytes changed and shifts the spans after the edit. Spans use UTF-16 offsets, matching `NSRange`. Each span has a role and an `isSyntax` flag.

`swift-markdown` 0.9.0 (Apache 2.0, cmark-gfm) is a development dependency of the `TextworkHighlightOracle` and `TextworkEditorBench` targets. It is not a product of the app target. We keep it so tests and the benchmark can compare a full CommonMark and GitHub-flavored parse. That is the decision record for this third-party package: it is justified for measurement, and it does not ship.

`AttributedString(markdown:)` is not the editor highlighter. It drops the markers. The read-only preview may use it because the preview is rendered text, not the source.

tree-sitter is not a dependency. We did not get a measured build; see the spike.

## Consequences

The editor binary does not vendor cmark or tree-sitter. Mode 2 and mode 3 can be painted from `isSyntax` without a new parse. The hand-rolled grammar is not a full CommonMark implementation: reference links, raw HTML, and some delimiter edge cases are plain text. If a manuscript hits those gaps often, the next step is to re-parse the dirty block with swift-markdown rather than to adopt tree-sitter. Revisit this decision if the macOS benchmark shows a middle-of-document keystroke in a 1 MB file taking longer than a frame after attribute painting is included.

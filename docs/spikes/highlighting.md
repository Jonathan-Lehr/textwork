# Spike: live Markdown highlighting

The editor shows raw Markdown. Highlighting runs on each keystroke. This spike chooses how.

Published timings come from the release build of `TextworkEditorBench` on the macOS GitHub Actions runner (`macos-26`, Xcode 26.6). They are copied into the results section from that job's `highlighting-benchmarks` artifact. Numbers that were not produced by that run are not in the table. A Linux machine was used to compile the package and run the unit tests while writing the spike. Those runs are not the published timings.

## What we need

Correctness for the constructs the MVP edits: hash and underline headings, emphasis and strong, code spans, fenced code, links, images, lists, block quotes, and tables.

Speed for one keystroke in a 10 KB, 100 KB, and 1 MB document. The benchmark document is repeated sections of those constructs, trimmed on a newline near the target size. It is not one giant paragraph. A keystroke in a single 1 MB paragraph would reparse that paragraph.

Dependency cost. Apple frameworks win unless a decision record says otherwise.

Fit for later modes. Mode 2 dims syntax characters. Mode 3 hides them except near the cursor. Both need punctuation ranges that are separate from content.

## Candidates

### Hand-rolled line and block highlighter (chosen)

`MarkdownHighlighter` in `Packages/TextworkEditor`. A byte scan splits lines, classifies each line, and groups lines into blocks. An inline scan, inside anything that is not code, finds code spans, links, images, autolinks, emphasis, reference links, and inline HTML. Emphasis uses a delimiter stack and ASCII flanking rules, including the multiple-of-three rule for `*` and `_`.

Reference links are `[text][label]`, the collapsed form `[text][]`, and the shortcut form `[text]`. A shortcut or collapsed link is highlighted only when its label is defined. Definitions are single lines of the form `[label]: destination` or `[label]: destination "title"`, recognized when they start a block. The label set is collected while lines are classified. A keystroke restyles a reused block only when a label it mentions was added or removed, so the rest of the document is not parsed again.

Raw HTML uses the `html` role. Inline tags, comments, processing instructions, declarations, and CDATA mark their delimiters as syntax and the tag or comment text as content. HTML blocks (CommonMark types 1–7, including script, comments, and block tags through the next blank line) are not scanned for Markdown emphasis.

Spans are UTF-16 ranges with a role and `isSyntax`. The Mac and iPad text views paint content first and syntax after, so markers stay visible in mode 1. Mode 2 and mode 3 are not implemented. They can read `isSyntax`.

A keystroke splices the byte buffer, then walks blocks from the start and from the end. Blocks whose bytes and kind still match are reused. Only the blocks that overlap the edit, plus blocks whose reference-link resolution changed, are styled again. Suffix spans are shifted by the UTF-16 delta. The snapshot records the UTF-16 ranges to repaint: those restyled blocks and the characters the edit inserted. Tests check that this matches a full highlight and that a middle insert reuses most blocks.

Known gaps, covered by the spike rather than hidden:

- Characters outside ASCII are treated as word characters for emphasis flanking, so Unicode punctuation does not follow the CommonMark flanking rules.
- List items are highlighted per line. A code span that starts on one list line does not continue on the next.
- Reference labels and definitions that span lines are plain text. A definition inside a block quote or a list item is not added to the label set. The preview parser does resolve definitions in those nested blocks.
- An HTML block is recognized at the start of a line. The same tags inside a list item or a block quote are inline tags, not a block.
- Setext headings and pipe tables are recognized. A thematic break is three or more `*`, `-`, or `_`.

### swift-markdown 0.9.0 (comparison, not shipped)

Apple's package, now under `swiftlang/swift-markdown`, parses with cmark-gfm and exposes `SourceRange` on each node. Columns are 1-based UTF-8 byte offsets on the line. `SwiftMarkdownHighlighter` walks the tree, turns text nodes into content spans, and treats the gaps around those children as syntax. Fenced and inline code use the node's literal to split markers from code.

The library reparses the whole document. It has no edit API, so a keystroke cost is a full parse plus the walk. That cost is what the benchmark reports. It is the right correctness oracle for CommonMark and GitHub-flavored Markdown, including tables. The app does not link it. [ADR 0004](../decisions/0004-syntax-highlighting.md) records it as a development dependency only.

### Foundation `AttributedString(markdown:)` (rejected for the editor)

On Apple platforms, `AttributedString(markdown:)` parses Markdown into rendered text. The markers are gone: `*emphasized*` becomes `emphasized`. `appliesSourcePositionAttributes` records where the rendered run came from in the source, and that position skips the marker characters. That is useful for a preview. It cannot color the `#` or the backticks in the buffer the user is editing.

The read-only preview card used this API when the spike was written. [ADR 0005](../decisions/0005-html-preview.md) replaces that preview with HTML. A unit test on macOS asserts that the markers are absent and that a source-position attribute exists. The Linux test run skips that test. The benchmark times the conversion only on the macOS runner, in `attributedStringMarkdown`. If that array is empty, the run was not on Apple platforms.

### tree-sitter-markdown (not measured)

tree-sitter parses incrementally and the Markdown grammars have explicit nodes for markers, which matches modes 2 and 3 well. Using it means shipping the tree-sitter C runtime plus the block and inline grammars.

We did not link a package and did not record timings. `SwiftTreeSitter` 0.25 depends on tree-sitter 0.25. `tree-sitter-markdown` 0.5.x was regenerated for tree-sitter 0.26. Pinning an older grammar just to force a number would not be the grammar we would ship, so the comparison stays qualitative: strongest incremental model, highest dependency cost, and not justified while the hand-rolled highlighter reuses blocks on a keystroke and stays inside Apple-free code in the app.

## Results

These medians are from the release build of `TextworkEditorBench` on GitHub Actions run `45067626906` (push of `8a32e12`, job `build-test`, macOS workflow). The artifact is `highlighting-benchmarks`. The runner was macOS 26.7.2 (build 25G332), arm64, 3 processors, Xcode 26.6 (17F113), Apple Swift 6.3.3. The 10 KB and 100 KB rows used 15 iterations. The 1 MB row used 9. The 95th percentile is in the artifact and does not change the ranking.

| Document | Hand-rolled full highlight | Hand-rolled keystroke | Blocks reparsed / reused | swift-markdown full parse (this is also its keystroke cost) | AttributedString conversion | AppKit paint of every span |
| --- | --- | --- | --- | --- | --- | --- |
| 9,973 bytes | 1.69 ms | 0.110 ms | 1 / 238 of 239 | 8.05 ms | 21.1 ms | 2.15 ms |
| 99,924 bytes | 22.5 ms | 0.988 ms | 1 / 2,387 of 2,388 | 57.5 ms | 188 ms | 6.86 ms |
| 999,989 bytes | 208 ms | 10.1 ms | 1 / 23,890 of 23,891 | 595 ms | 1,652 ms | 81.7 ms |

`AttributedString` also shows the source is consumed. At 9,973 source characters the rendered string was 5,957 characters. The same ratio holds at the larger sizes. That conversion was measured on the CI run above. It does not run on Linux, where the unit test is skipped.

Painting is separate from parsing. On that CI run, replacing attributes for every span was 81.7 ms at about 1 MB, larger than the 10.1 ms incremental parse. The editor now repaints the invalidated range instead. The Mac measurements below are that change. A full swift-markdown parse of the same file was 595 ms on CI before any painting, so the parser choice is unchanged.

No other machine's timings are in the CI table. A debug build on Linux was used only to see that the executable ran while the spike was first written. Those numbers are not recorded here.

### Measured on Jonathan's Mac

Two release runs of `TextworkEditorBench`, same document shape as the CI table. The host was macOS 26.6.2 (build 25G83), arm64, 10 processors, Apple Swift 6.4 (swiftlang-6.4.0.34.1). The 10 KB and 100 KB rows used 15 iterations. The 1 MB row used 9. Milliseconds below are medians rounded to three decimal places. The benchmark document does not contain reference links or raw HTML, so the keystroke row is the cost of recognizing those constructs, not a document full of them.

Before reference-link highlighting, raw HTML, and range repaint:

| Document | Hand-rolled full highlight | Hand-rolled keystroke | Blocks reparsed / reused | swift-markdown full parse | AttributedString conversion | AppKit paint of every span |
| --- | --- | --- | --- | --- | --- | --- |
| 9,973 bytes | 1.413 ms | 0.083 ms | 1 / 238 of 239 | 2.731 ms | 5.940 ms | 0.718 ms |
| 99,924 bytes | 9.264 ms | 0.674 ms | 1 / 2,387 of 2,388 | 25.859 ms | 64.538 ms | 3.733 ms |
| 999,989 bytes | 94.856 ms | 7.125 ms | 1 / 23,890 of 23,891 | 263.312 ms | 719.688 ms | 37.223 ms |

After those changes, on the same machine and toolchain. `AppKit paint of every span` is the old whole-buffer update, still measured. `AppKit paint of invalidated range` is the editor path. The invalidated length is UTF-16 code units for one inserted `Z` in the middle of the document.

| Document | Hand-rolled full highlight | Hand-rolled keystroke | Blocks reparsed / reused | AppKit paint of every span | AppKit paint of invalidated range | Invalidated UTF-16 length |
| --- | --- | --- | --- | --- | --- | --- |
| 9,973 bytes | 2.022 ms | 0.115 ms | 1 / 238 of 239 | 0.751 ms | 0.013 ms | 11 |
| 99,924 bytes | 9.752 ms | 0.700 ms | 1 / 2,387 of 2,388 | 3.759 ms | 0.016 ms | 41 |
| 999,989 bytes | 98.075 ms | 7.364 ms | 1 / 23,890 of 23,891 | 36.548 ms | 0.203 ms | 128 |

The same after run also measured swift-markdown at 3.026 ms, 26.162 ms, and 262.212 ms, and `AttributedString` conversion at 5.872 ms, 64.506 ms, and 719.247 ms. Rendered character counts were 5,957, 59,682, and 597,259. Those parsers did not change. The spread against the before run on this Mac is run-to-run variation.

At 1 MB the whole-buffer paint stayed about 37 ms. Painting the invalidated range, 128 UTF-16 code units, was 0.203 ms. The keystroke highlight moved from 7.125 ms to 7.364 ms and still reparsed one block.

## Recommendation

Use the hand-rolled highlighter in the app. It is incremental, it labels syntax for modes 2 and 3, and the app binary does not take a third-party parser. Keep swift-markdown as the oracle and the benchmark comparison. The preview no longer uses `AttributedString(markdown:)`; see ADR 0005. Do not add tree-sitter unless a later measurement shows the hand-rolled keystroke path missing frames on a 1 MB file after painting is included, and a matched tree-sitter build beats it by enough to justify the C dependency.

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

`MarkdownHighlighter` in `Packages/TextworkEditor`. A byte scan splits lines, classifies each line, and groups lines into blocks. An inline scan, inside anything that is not code, finds code spans, links, images, autolinks, and emphasis. Emphasis uses a delimiter stack and ASCII flanking rules, including the multiple-of-three rule for `*` and `_`.

Spans are UTF-16 ranges with a role and `isSyntax`. The Mac and iPad text views paint content first and syntax after, so markers stay visible in mode 1. Mode 2 and mode 3 are not implemented. They can read `isSyntax`.

A keystroke splices the byte buffer, then walks blocks from the start and from the end. Blocks whose bytes and kind still match are reused. Only the blocks that overlap the edit are styled again. Suffix spans are shifted by the UTF-16 delta. Tests check that this matches a full highlight and that a middle insert reuses most blocks.

Known gaps, covered by the spike rather than hidden:

- Reference-style links (`[text][id]`) are not highlighted. Inline links, images, `<https://...>` autolinks, and bare `https://` URLs are.
- Raw HTML is ordinary paragraph text.
- Characters outside ASCII are treated as word characters for emphasis flanking, so Unicode punctuation does not follow the CommonMark flanking rules.
- List items are highlighted per line. A code span that starts on one list line does not continue on the next.
- Setext headings and pipe tables are recognized. A thematic break is three or more `*`, `-`, or `_`.

### swift-markdown 0.9.0 (comparison, not shipped)

Apple's package, now under `swiftlang/swift-markdown`, parses with cmark-gfm and exposes `SourceRange` on each node. Columns are 1-based UTF-8 byte offsets on the line. `SwiftMarkdownHighlighter` walks the tree, turns text nodes into content spans, and treats the gaps around those children as syntax. Fenced and inline code use the node's literal to split markers from code.

The library reparses the whole document. It has no edit API, so a keystroke cost is a full parse plus the walk. That cost is what the benchmark reports. It is the right correctness oracle for CommonMark and GitHub-flavored Markdown, including tables. The app does not link it. [ADR 0004](../decisions/0004-syntax-highlighting.md) records it as a development dependency only.

### Foundation `AttributedString(markdown:)` (rejected for the editor)

On Apple platforms, `AttributedString(markdown:)` parses Markdown into rendered text. The markers are gone: `*emphasized*` becomes `emphasized`. `appliesSourcePositionAttributes` records where the rendered run came from in the source, and that position skips the marker characters. That is useful for a preview. It cannot color the `#` or the backticks in the buffer the user is editing.

The read-only preview card uses this API. A unit test on macOS asserts that the markers are absent and that a source-position attribute exists. The Linux test run skips that test. The benchmark times the conversion only on the macOS runner, in `attributedStringMarkdown`. If that array is empty, the run was not on Apple platforms.

### tree-sitter-markdown (not measured)

tree-sitter parses incrementally and the Markdown grammars have explicit nodes for markers, which matches modes 2 and 3 well. Using it means shipping the tree-sitter C runtime plus the block and inline grammars.

We did not link a package and did not record timings. `SwiftTreeSitter` 0.25 depends on tree-sitter 0.25. `tree-sitter-markdown` 0.5.x was regenerated for tree-sitter 0.26. Pinning an older grammar just to force a number would not be the grammar we would ship, so the comparison stays qualitative: strongest incremental model, highest dependency cost, and not justified while the hand-rolled highlighter reuses blocks on a keystroke and stays inside Apple-free code in the app.

## Results

The table is filled from `benchmark-results.json` produced by `.github/workflows/macos.yml`. Each cell is the median of the release-build samples. The 1 MB cases use 9 iterations. The smaller cases use 15. The 95th percentile is the `percentile95Milliseconds` field in the JSON artifact and is not repeated here unless it changes the conclusion.

| Document | Hand-rolled full highlight | Hand-rolled keystroke | Blocks reparsed / reused | swift-markdown full parse (this is also its keystroke cost) | AttributedString conversion | AppKit paint of every span |
| --- | --- | --- | --- | --- | --- | --- |
| ~10 KB | pending macOS CI | pending macOS CI | pending macOS CI | pending macOS CI | pending macOS CI | pending macOS CI |
| ~100 KB | pending macOS CI | pending macOS CI | pending macOS CI | pending macOS CI | pending macOS CI | pending macOS CI |
| ~1 MB | pending macOS CI | pending macOS CI | pending macOS CI | pending macOS CI | pending macOS CI | pending macOS CI |

Host, Swift version, iteration counts, and p95 values are in the same artifact, next to `swift-version.txt` from that job. Do not replace this table with timings from any other machine.

## Recommendation

Use the hand-rolled highlighter in the app. It is incremental, it labels syntax for modes 2 and 3, and the app binary does not take a third-party parser. Keep swift-markdown as the oracle and the benchmark comparison. Keep `AttributedString(markdown:)` for the preview only. Do not add tree-sitter unless a later measurement shows the hand-rolled keystroke path missing frames on a 1 MB file after painting is included, and a matched tree-sitter build beats it by enough to justify the C dependency.

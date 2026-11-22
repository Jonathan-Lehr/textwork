# ADR 0003: Plain Markdown files

- Status: Accepted
- Date: 2026-11-22

## Context

The MVP is one file at a time: a better TextEdit for Markdown. Later, a project is a folder of those files with a compile step. Highlights, fonts, and the preview are presentation. They must not leak into the saved file, or the file stops being portable Markdown.

## Decision

Save only UTF-8 `.md` files. The document type is `net.daringfireball.markdown`. The file wrapper writes `Data(text.utf8)` and reads it back as a `String`. Attributes on the text view are for display.

The preview reads the same string and renders it. It is not a second document and it is not editable.

Images in the MVP are paths relative to the Markdown file. There is no asset catalog inside the document.

## Consequences

Any editor can open a Textwork file. Highlighting can be recomputed from the source. We do not store ordering, comments, or snapshots inside the file in the MVP. Phase 2 ordering has to live somewhere a folder of Markdown files can express, which this decision leaves open on purpose.

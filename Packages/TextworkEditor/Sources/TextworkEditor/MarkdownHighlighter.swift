/// Incremental Markdown highlighter used by the editor.
///
/// The app links this type and nothing else. Parsing is a line-oriented block
/// pass plus an inline pass. A keystroke reparses only the blocks whose bytes
/// changed; later blocks keep their spans, shifted to the new UTF-16 offsets.
public struct MarkdownHighlighter: Sendable {
    public init() {}

    public func highlight(_ text: String) -> HighlightSnapshot {
        assemble(bytes: Array(text.utf8), previous: nil, editByteStart: 0, editByteEnd: 0, utf16Delta: 0)
    }

    public func apply(_ edit: MarkdownEdit, to snapshot: HighlightSnapshot) -> HighlightSnapshot {
        let utf16Count = snapshot.utf16Count
        let lower = min(max(edit.range.lowerBound, 0), utf16Count)
        let upper = min(max(edit.range.upperBound, lower), utf16Count)
        let startByte = DocumentBuffer.byteOffset(forUTF16: lower, bytes: snapshot.bytes, lines: snapshot.lines)
        let endByte = DocumentBuffer.byteOffset(forUTF16: upper, bytes: snapshot.bytes, lines: snapshot.lines)
        let replacement = Array(edit.replacement.utf8)
        var bytes = snapshot.bytes
        bytes.replaceSubrange(startByte..<endByte, with: replacement)
        let insertedEnd = startByte + replacement.count
        let utf16Delta = edit.replacement.utf16.count - (upper - lower)
        return assemble(
            bytes: bytes,
            previous: snapshot,
            editByteStart: startByte,
            editByteEnd: insertedEnd,
            utf16Delta: utf16Delta
        )
    }

    private func assemble(
        bytes: [UInt8],
        previous: HighlightSnapshot?,
        editByteStart: Int,
        editByteEnd: Int,
        utf16Delta: Int
    ) -> HighlightSnapshot {
        var lines = DocumentBuffer.lines(in: bytes)
        DocumentBuffer.classify(&lines, bytes: bytes)
        let structures = DocumentBuffer.group(lines, bytes: bytes)
        let ranges = structures.map { BlockStyler.contentByteRange(lines: lines, startLine: $0.start, endLine: $0.end) }

        let spansByIndex = reusePlan(
            structures: structures,
            ranges: ranges,
            bytes: bytes,
            lines: lines,
            previous: previous,
            editByteStart: editByteStart,
            editByteEnd: editByteEnd,
            utf16Delta: utf16Delta
        )

        var blocks: [StyledBlock] = []
        blocks.reserveCapacity(structures.count)
        var reparsed = 0
        for index in structures.indices {
            let structure = structures[index]
            if let existing = spansByIndex[index] {
                blocks.append(
                    StyledBlock(
                        startLine: structure.start,
                        endLine: structure.end,
                        kind: structure.kind,
                        spans: existing
                    )
                )
            } else {
                reparsed += 1
                blocks.append(
                    StyledBlock(
                        startLine: structure.start,
                        endLine: structure.end,
                        kind: structure.kind,
                        spans: BlockStyler.style(
                            bytes: bytes,
                            lines: lines,
                            startLine: structure.start,
                            endLine: structure.end,
                            kind: structure.kind
                        )
                    )
                )
            }
        }

        var spans: [HighlightSpan] = []
        spans.reserveCapacity(blocks.reduce(0) { $0 + $1.spans.count })
        for block in blocks {
            spans.append(contentsOf: block.spans)
        }
        spans.sort(by: spanPrecedes)

        return HighlightSnapshot(
            spans: spans,
            statistics: HighlightStatistics(
                blockCount: blocks.count,
                blocksReparsed: reparsed,
                blocksReused: blocks.count - reparsed
            ),
            bytes: bytes,
            lines: lines,
            blocks: blocks
        )
    }

    private func reusePlan(
        structures: [(start: Int, end: Int, kind: StructureKind)],
        ranges: [Range<Int>],
        bytes: [UInt8],
        lines: [TextLine],
        previous: HighlightSnapshot?,
        editByteStart: Int,
        editByteEnd: Int,
        utf16Delta: Int
    ) -> [Int: [HighlightSpan]] {
        guard let previous, previous.bytes.count + (editByteEnd - editByteStart) >= 0 else {
            return [:]
        }
        let byteDelta = (editByteEnd - editByteStart) - removedByteCount(previous: previous, editByteStart: editByteStart, editByteEnd: editByteEnd, newCount: bytes.count)
        var spansByIndex: [Int: [HighlightSpan]] = [:]

        var oldIndex = 0
        var newIndex = 0
        while newIndex < structures.count, oldIndex < previous.blocks.count {
            let oldBlock = previous.blocks[oldIndex]
            guard ranges[newIndex].upperBound <= editByteStart,
                  blocksMatch(oldBlock, previous: previous, newRange: ranges[newIndex], newBytes: bytes, byteDelta: 0),
                  oldBlock.kind == structures[newIndex].kind
            else { break }
            spansByIndex[newIndex] = oldBlock.spans
            oldIndex += 1
            newIndex += 1
        }

        var oldEnd = previous.blocks.count
        var newEnd = structures.count
        while newEnd > newIndex, oldEnd > oldIndex {
            let oldBlock = previous.blocks[oldEnd - 1]
            guard ranges[newEnd - 1].lowerBound >= editByteEnd,
                  blocksMatch(oldBlock, previous: previous, newRange: ranges[newEnd - 1], newBytes: bytes, byteDelta: byteDelta),
                  oldBlock.kind == structures[newEnd - 1].kind
            else { break }
            spansByIndex[newEnd - 1] = oldBlock.spans.map { $0.shifted(by: utf16Delta) }
            oldEnd -= 1
            newEnd -= 1
        }
        _ = lines
        return spansByIndex
    }

    private func removedByteCount(previous: HighlightSnapshot, editByteStart: Int, editByteEnd: Int, newCount: Int) -> Int {
        // newCount = oldCount - removed + inserted, inserted = editByteEnd - editByteStart
        let inserted = editByteEnd - editByteStart
        return previous.bytes.count + inserted - newCount
    }

    private func blocksMatch(
        _ oldBlock: StyledBlock,
        previous: HighlightSnapshot,
        newRange: Range<Int>,
        newBytes: [UInt8],
        byteDelta: Int
    ) -> Bool {
        let oldRange = BlockStyler.contentByteRange(lines: previous.lines, startLine: oldBlock.startLine, endLine: oldBlock.endLine)
        guard oldRange.count == newRange.count else { return false }
        guard oldRange.lowerBound + byteDelta == newRange.lowerBound else { return false }
        guard oldRange.upperBound <= previous.bytes.count, newRange.upperBound <= newBytes.count else { return false }
        return previous.bytes[oldRange] == newBytes[newRange]
    }
}

private func spanPrecedes(_ lhs: HighlightSpan, _ rhs: HighlightSpan) -> Bool {
    if lhs.startUTF16 != rhs.startUTF16 { return lhs.startUTF16 < rhs.startUTF16 }
    if lhs.endUTF16 != rhs.endUTF16 { return lhs.endUTF16 < rhs.endUTF16 }
    if lhs.isSyntax != rhs.isSyntax { return lhs.isSyntax && !rhs.isSyntax }
    return lhs.role.rawValue < rhs.role.rawValue
}

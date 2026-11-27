/// Incremental Markdown highlighter used by the editor.
///
/// The app links this type and nothing else. Parsing is a line-oriented block
/// pass plus an inline pass. A keystroke reparses only the blocks whose bytes
/// changed; later blocks keep their spans, shifted to the new UTF-16 offsets.
public struct MarkdownHighlighter: Sendable {
    public init() {}

    public func highlight(_ text: String) -> HighlightSnapshot {
        assemble(
            bytes: Array(text.utf8),
            previous: nil,
            editByteStart: 0,
            editByteEnd: 0,
            utf16Delta: 0,
            editedUTF16: nil
        )
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
        let editedUTF16 = lower..<(lower + edit.replacement.utf16.count)
        return assemble(
            bytes: bytes,
            previous: snapshot,
            editByteStart: startByte,
            editByteEnd: insertedEnd,
            utf16Delta: utf16Delta,
            editedUTF16: editedUTF16
        )
    }

    private func assemble(
        bytes: [UInt8],
        previous: HighlightSnapshot?,
        editByteStart: Int,
        editByteEnd: Int,
        utf16Delta: Int,
        editedUTF16: Range<Int>?
    ) -> HighlightSnapshot {
        var lines = DocumentBuffer.lines(in: bytes)
        DocumentBuffer.classify(&lines, bytes: bytes)
        let definedLabels = DocumentBuffer.definedReferenceLabels(lines: lines, bytes: bytes)
        let structures = DocumentBuffer.group(lines, bytes: bytes)
        let ranges = structures.map { BlockStyler.contentByteRange(lines: lines, startLine: $0.start, endLine: $0.end) }

        var reused = reusePlan(
            structures: structures,
            ranges: ranges,
            bytes: bytes,
            previous: previous,
            editByteStart: editByteStart,
            editByteEnd: editByteEnd,
            utf16Delta: utf16Delta
        )
        let changedLabels = previous.map { definedLabels.symmetricDifference($0.definedReferenceLabels) } ?? []
        if !changedLabels.isEmpty {
            let stale = reused.keys.filter { index in
                let labels = reused[index]?.candidateLabels ?? []
                return labels.contains(where: { changedLabels.contains($0) })
            }
            for index in stale {
                reused.removeValue(forKey: index)
            }
        }

        var blocks: [StyledBlock] = []
        blocks.reserveCapacity(structures.count)
        var reparsed = 0
        var invalidated: [Range<Int>] = []
        for index in structures.indices {
            let structure = structures[index]
            if let existing = reused[index] {
                blocks.append(
                    StyledBlock(
                        startLine: structure.start,
                        endLine: structure.end,
                        kind: structure.kind,
                        spans: existing.spans,
                        candidateLabels: existing.candidateLabels
                    )
                )
            } else {
                reparsed += 1
                let styled = BlockStyler.style(
                    bytes: bytes,
                    lines: lines,
                    startLine: structure.start,
                    endLine: structure.end,
                    kind: structure.kind,
                    definedLabels: definedLabels
                )
                blocks.append(
                    StyledBlock(
                        startLine: structure.start,
                        endLine: structure.end,
                        kind: structure.kind,
                        spans: styled.spans,
                        candidateLabels: styled.candidateLabels
                    )
                )
                if structure.start < structure.end {
                    let start = lines[structure.start].utf16Start
                    let end = lines[structure.end - 1].utf16End
                    if end > start { invalidated.append(start..<end) }
                }
            }
        }

        var spans: [HighlightSpan] = []
        spans.reserveCapacity(blocks.reduce(0) { $0 + $1.spans.count })
        for block in blocks {
            spans.append(contentsOf: block.spans)
        }
        spans.sort(by: spanPrecedes)

        let utf16Count = lines.last.map { $0.utf16Start + $0.utf16Count + $0.newlineUTF16Count } ?? 0
        let invalidatedRanges: [Range<Int>]
        if previous == nil {
            invalidatedRanges = utf16Count > 0 ? [0..<utf16Count] : []
        } else {
            if let editedUTF16, !editedUTF16.isEmpty { invalidated.append(editedUTF16) }
            invalidatedRanges = mergeRanges(invalidated)
        }

        return HighlightSnapshot(
            spans: spans,
            statistics: HighlightStatistics(
                blockCount: blocks.count,
                blocksReparsed: reparsed,
                blocksReused: blocks.count - reparsed
            ),
            invalidatedUTF16Ranges: invalidatedRanges,
            bytes: bytes,
            lines: lines,
            blocks: blocks,
            definedReferenceLabels: definedLabels
        )
    }

    private struct ReusedStyle {
        var spans: [HighlightSpan]
        var candidateLabels: [String]
    }

    private func reusePlan(
        structures: [(start: Int, end: Int, kind: StructureKind)],
        ranges: [Range<Int>],
        bytes: [UInt8],
        previous: HighlightSnapshot?,
        editByteStart: Int,
        editByteEnd: Int,
        utf16Delta: Int
    ) -> [Int: ReusedStyle] {
        guard let previous, previous.bytes.count + (editByteEnd - editByteStart) >= 0 else { return [:] }
        let byteDelta = (editByteEnd - editByteStart) - removedByteCount(previous: previous, editByteStart: editByteStart, editByteEnd: editByteEnd, newCount: bytes.count)
        var reused: [Int: ReusedStyle] = [:]

        var oldIndex = 0
        var newIndex = 0
        while newIndex < structures.count, oldIndex < previous.blocks.count {
            let oldBlock = previous.blocks[oldIndex]
            guard ranges[newIndex].upperBound <= editByteStart,
                  blocksMatch(oldBlock, previous: previous, newRange: ranges[newIndex], newBytes: bytes, byteDelta: 0),
                  oldBlock.kind == structures[newIndex].kind
            else { break }
            reused[newIndex] = ReusedStyle(spans: oldBlock.spans, candidateLabels: oldBlock.candidateLabels)
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
            reused[newEnd - 1] = ReusedStyle(
                spans: oldBlock.spans.map { $0.shifted(by: utf16Delta) },
                candidateLabels: oldBlock.candidateLabels
            )
            oldEnd -= 1
            newEnd -= 1
        }
        return reused
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

private func mergeRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
    let sorted = ranges.filter { !$0.isEmpty }.sorted { $0.lowerBound < $1.lowerBound }
    var merged: [Range<Int>] = []
    for range in sorted {
        if let last = merged.last, last.upperBound >= range.lowerBound {
            merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
        } else {
            merged.append(range)
        }
    }
    return merged
}

private func spanPrecedes(_ lhs: HighlightSpan, _ rhs: HighlightSpan) -> Bool {
    if lhs.startUTF16 != rhs.startUTF16 { return lhs.startUTF16 < rhs.startUTF16 }
    // A wider span is painted first so a token that starts on the same character
    // can replace its foreground color.
    if lhs.endUTF16 != rhs.endUTF16 { return lhs.endUTF16 > rhs.endUTF16 }
    if lhs.isSyntax != rhs.isSyntax { return lhs.isSyntax && !rhs.isSyntax }
    return lhs.role.rawValue < rhs.role.rawValue
}

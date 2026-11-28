#if os(macOS)
import AppKit
import TextworkEditor

final class MarkdownSourceTextView: NSTextView {
    var spellingExclusions: [Range<Int>] = []
    private var isCheckingSpelling = false

    override func checkSpelling(_ sender: Any?) {
        if isCheckingSpelling { return }
        if spellingExclusions.isEmpty {
            super.checkSpelling(sender)
            return
        }
        isCheckingSpelling = true
        defer { isCheckingSpelling = false }
        selectNextMisspelling()
    }

    private func selectNextMisspelling() {
        let storage = string as NSString
        let length = storage.length
        guard length > 0 else {
            NSSound.beep()
            return
        }
        let bounds = selectionBounds(length: length)
        if let found = nextMisspelling(in: storage, from: bounds.end, until: length) {
            selectMisspelling(found, in: storage)
            return
        }
        // The selected word starts at bounds.start, so it is outside this window.
        if let found = nextMisspelling(in: storage, from: 0, until: bounds.start) {
            selectMisspelling(found, in: storage)
            return
        }
        NSSound.beep()
    }

    private func nextMisspelling(in storage: NSString, from start: Int, until end: Int) -> NSRange? {
        guard end > start else { return nil }
        let length = storage.length
        let results = NSSpellChecker.shared.check(
            string,
            range: NSRange(location: start, length: end - start),
            types: NSTextCheckingResult.CheckingType.spelling.rawValue,
            options: nil,
            inSpellDocumentWithTag: spellCheckerDocumentTag,
            orthography: nil,
            wordCount: nil
        )
        for result in results where result.resultType.contains(.spelling) {
            let range = result.range
            guard rangeFits(range, length: length), range.location >= start, range.location < end else { continue }
            let swiftRange = range.location..<(range.location + range.length)
            if SpellingExclusion.covers(swiftRange, exclusions: spellingExclusions) { continue }
            return range
        }
        return nil
    }

    private func selectionBounds(length: Int) -> (start: Int, end: Int) {
        let selection = selectedRange()
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0 else { return (0, 0) }
        guard selection.location <= length else { return (length, length) }
        let remaining = length - selection.location
        let boundedLength = min(selection.length, remaining)
        return (selection.location, selection.location + boundedLength)
    }

    private func rangeFits(_ range: NSRange, length: Int) -> Bool {
        guard range.location != NSNotFound, range.location >= 0, range.length > 0 else { return false }
        guard range.location <= length, range.length <= length - range.location else { return false }
        return true
    }

    private func selectMisspelling(_ range: NSRange, in storage: NSString) {
        guard rangeFits(range, length: storage.length) else { return }
        let word = storage.substring(with: range)
        NSSpellChecker.shared.updateSpellingPanel(withMisspelledWord: word)
        setSelectedRange(range)
        scrollRangeToVisible(range)
    }
}
#endif

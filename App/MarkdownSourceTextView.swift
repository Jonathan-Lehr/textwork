#if os(macOS)
import AppKit
import TextworkEditor

final class MarkdownSourceTextView: NSTextView {
    var spellingExclusions: [Range<Int>] = []

    override func checkSpelling(_ sender: Any?) {
        if spellingExclusions.isEmpty {
            super.checkSpelling(sender)
            return
        }
        selectNextMisspelling()
    }

    private func selectNextMisspelling() {
        let storage = string as NSString
        let length = storage.length
        guard length > 0 else {
            NSSound.beep()
            return
        }
        let origin = min(NSMaxRange(selectedRange()), length)
        if let found = nextMisspelling(from: origin, until: length) {
            selectMisspelling(found, in: storage)
            return
        }
        if origin > 0, let found = nextMisspelling(from: 0, until: origin) {
            selectMisspelling(found, in: storage)
            return
        }
        NSSound.beep()
    }

    private func nextMisspelling(from start: Int, until end: Int) -> NSRange? {
        guard end > start else { return nil }
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
            guard range.location != NSNotFound, range.length > 0 else { continue }
            let swiftRange = range.location..<(range.location + range.length)
            if !SpellingExclusion.covers(swiftRange, exclusions: spellingExclusions) { return range }
        }
        return nil
    }

    private func selectMisspelling(_ range: NSRange, in storage: NSString) {
        let word = storage.substring(with: range)
        NSSpellChecker.shared.updateSpellingPanel(withMisspelledWord: word)
        setSelectedRange(range)
        scrollRangeToVisible(range)
    }
}
#endif

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
        var searchStart = origin
        var hasWrapped = false
        var previousStart = -1
        while true {
            if searchStart == previousStart {
                NSSound.beep()
                return
            }
            previousStart = searchStart
            let found = NSSpellChecker.shared.checkSpelling(
                of: string,
                startingAt: searchStart,
                language: nil,
                wrap: false,
                inSpellDocumentWithTag: spellCheckerDocumentTag,
                wordCount: nil
            )
            if found.location == NSNotFound || found.length <= 0 {
                if hasWrapped {
                    NSSound.beep()
                    return
                }
                hasWrapped = true
                searchStart = 0
                continue
            }
            if hasWrapped, found.location >= origin {
                NSSound.beep()
                return
            }
            let swiftRange = found.location..<(found.location + found.length)
            if !SpellingExclusion.covers(swiftRange, exclusions: spellingExclusions) {
                let word = storage.substring(with: found)
                NSSpellChecker.shared.updateSpellingPanel(withMisspelledWord: word)
                setSelectedRange(found)
                scrollRangeToVisible(found)
                return
            }
            let next = NSMaxRange(found)
            if next <= searchStart {
                NSSound.beep()
                return
            }
            if hasWrapped, next >= origin {
                NSSound.beep()
                return
            }
            searchStart = next
        }
    }
}
#endif

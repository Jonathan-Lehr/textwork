import Foundation
import XCTest
@testable import TextworkEditor

final class SpellingExclusionTests: XCTestCase {
    private let highlighter = MarkdownHighlighter()

    func testInlineCodeIsExcludedAndSurroundingWordsAreNot() {
        let text = "A misstake beside `alsoo wrong` and then misstake."
        let exclusions = exclusions(in: text)
        XCTAssertTrue(covers("alsoo", in: text, exclusions: exclusions))
        XCTAssertTrue(covers("wrong", in: text, exclusions: exclusions))
        let prose = utf16Ranges(of: "misstake", in: text)
        XCTAssertEqual(prose.count, 2)
        for range in prose {
            XCTAssertFalse(SpellingExclusion.covers(range, exclusions: exclusions))
        }
    }

    func testDoubleBacktickCodeSpanIsExcluded() {
        let text = "Keep misstake and ``alsoo`` apart."
        let exclusions = exclusions(in: text)
        XCTAssertTrue(covers("alsoo", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("misstake", in: text, exclusions: exclusions))
    }

    func testFencedCodeBlockIsExcludedAndProseIsNot() {
        let text = """
        A misstake in prose.

        ```swift
        let misstake = 1
        ```

        After the fence, misstake remains.
        """
        let exclusions = exclusions(in: text)
        let ranges = utf16Ranges(of: "misstake", in: text)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertFalse(SpellingExclusion.covers(ranges[0], exclusions: exclusions))
        XCTAssertTrue(SpellingExclusion.covers(ranges[1], exclusions: exclusions))
        XCTAssertFalse(SpellingExclusion.covers(ranges[2], exclusions: exclusions))
        XCTAssertTrue(covers("let", in: text, exclusions: exclusions))
    }

    func testIndentedCodeBlockIsExcluded() {
        let text = "A misstake in prose.\n\n    indented misstake\n"
        let exclusions = exclusions(in: text)
        let ranges = utf16Ranges(of: "misstake", in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertFalse(SpellingExclusion.covers(ranges[0], exclusions: exclusions))
        XCTAssertTrue(SpellingExclusion.covers(ranges[1], exclusions: exclusions))
    }

    func testBareURLAutolinkAndLinkDestinationAreExcluded() {
        let text = "See https://examplle.com/docs and <https://otherr.example> plus [Labell](https://targett.example/a) please."
        let exclusions = exclusions(in: text)
        XCTAssertTrue(covers("examplle", in: text, exclusions: exclusions))
        XCTAssertTrue(covers("otherr", in: text, exclusions: exclusions))
        XCTAssertTrue(covers("targett", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("Labell", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("please", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("See", in: text, exclusions: exclusions))
    }

    func testInlineLinkTitleStaysEligible() {
        let text = "[Labell](https://examplle.com \"misstake in title\")"
        let exclusions = exclusions(in: text)
        XCTAssertFalse(covers("Labell", in: text, exclusions: exclusions))
        XCTAssertTrue(covers("examplle", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("misstake", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("title", in: text, exclusions: exclusions))
    }

    func testAngleDestinationLeavesTheTitleEligible() {
        let text = "[Labell](<https://examplle.com> \"misstake\")"
        let exclusions = exclusions(in: text)
        XCTAssertTrue(covers("examplle", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("Labell", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("misstake", in: text, exclusions: exclusions))
    }

    func testReferenceLinkTargetIsExcluded() {
        let text = """
        [example]: https://examplle.com

        [Labell][example]
        """
        let exclusions = exclusions(in: text)
        XCTAssertTrue(covers("examplle", in: text, exclusions: exclusions))
        XCTAssertTrue(covers("][example]", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("Labell", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("[example]", in: text, exclusions: exclusions))
    }

    func testReferenceDefinitionDestinationIsExcludedAndTitleIsNot() {
        let text = "[Labell]: /urll \"misstake in title\""
        let exclusions = exclusions(in: text)
        XCTAssertFalse(covers("Labell", in: text, exclusions: exclusions))
        XCTAssertTrue(covers("urll", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("misstake", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("title", in: text, exclusions: exclusions))
    }

    func testEmailAutolinkIsExcluded() {
        let text = "Write <misstake@example.com> today."
        let exclusions = exclusions(in: text)
        XCTAssertTrue(covers("misstake", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("today", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("Write", in: text, exclusions: exclusions))
    }

    func testImageDestinationIsExcludedAndDescriptionIsNot() {
        let text = "![misstake here](images/figur.png)"
        let exclusions = exclusions(in: text)
        XCTAssertFalse(covers("misstake", in: text, exclusions: exclusions))
        XCTAssertFalse(covers("here", in: text, exclusions: exclusions))
        XCTAssertTrue(covers("figur", in: text, exclusions: exclusions))
    }

    func testEmphasisIsNotExcluded() {
        let text = "A *misstake* and a **misstake** stay visible."
        let exclusions = exclusions(in: text)
        let ranges = utf16Ranges(of: "misstake", in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertTrue(ranges.allSatisfy { !SpellingExclusion.covers($0, exclusions: exclusions) })
    }

    func testCheckingResultsInsideCodeAndURLsAreDropped() {
        let text = "misstake and `misstake` and https://examplle.com"
        let exclusions = exclusions(in: text)
        let prose = utf16Range(of: "misstake", in: text)
        let code = utf16Ranges(of: "misstake", in: text)[1]
        let url = utf16Range(of: "examplle", in: text)
        let orthography = NSOrthography(dominantScript: "Latn", languageMap: ["Latn": ["en"]])
        let results = [
            NSTextCheckingResult.spellCheckingResult(range: nsRange(prose)),
            NSTextCheckingResult.spellCheckingResult(range: nsRange(code)),
            NSTextCheckingResult.grammarCheckingResult(range: nsRange(code), details: []),
            NSTextCheckingResult.correctionCheckingResult(range: nsRange(url), replacementString: "example"),
            NSTextCheckingResult.orthographyCheckingResult(range: NSRange(location: 0, length: 8), orthography: orthography),
        ]
        let kept = SpellingExclusion.includedCheckingResults(results, skipping: exclusions)
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(kept[0].resultType, .spelling)
        XCTAssertEqual(kept[0].range.location, prose.lowerBound)
        XCTAssertEqual(kept[1].resultType, .orthography)
    }

    private func exclusions(in text: String) -> [Range<Int>] {
        SpellingExclusion.ranges(in: highlighter.highlight(text))
    }

    private func covers(_ needle: String, in text: String, exclusions: [Range<Int>]) -> Bool {
        SpellingExclusion.covers(utf16Range(of: needle, in: text), exclusions: exclusions)
    }

    private func utf16Range(of needle: String, in text: String) -> Range<Int> {
        let ranges = utf16Ranges(of: needle, in: text)
        XCTAssertFalse(ranges.isEmpty, needle)
        return ranges[0]
    }

    private func utf16Ranges(of needle: String, in text: String) -> [Range<Int>] {
        let storage = text as NSString
        var ranges: [Range<Int>] = []
        var search = NSRange(location: 0, length: storage.length)
        while search.length > 0 {
            let found = storage.range(of: needle, range: search)
            if found.location == NSNotFound { break }
            ranges.append(found.location..<(found.location + found.length))
            let next = found.location + found.length
            search = NSRange(location: next, length: storage.length - next)
        }
        return ranges
    }

    private func nsRange(_ range: Range<Int>) -> NSRange {
        NSRange(location: range.lowerBound, length: range.count)
    }
}

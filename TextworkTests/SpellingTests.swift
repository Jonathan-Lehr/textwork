import AppKit
import SwiftUI
import XCTest

@MainActor
final class SpellingTests: XCTestCase {
    private var documentText = ""

    override func setUp() async throws {
        try await super.setUp()
        let application = NSApplication.shared
        if application.activationPolicy() != .accessory { application.setActivationPolicy(.accessory) }
        if !application.isRunning { application.finishLaunching() }
    }

    func testContinuousSpellCheckingStaysOnUntilTheUserTurnsItOff() {
        let textView = MarkdownSourceTextView(usingTextLayoutManager: true)
        let configuration = EditorConfiguration.standard
        configuration.apply(to: textView)
        configuration.enableContinuousSpellChecking(on: textView)
        XCTAssertTrue(textView.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(textView.isGrammarCheckingEnabled)
        XCTAssertFalse(textView.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(textView.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
        let spelling = NSTextCheckingResult.CheckingType.spelling.rawValue
        XCTAssertNotEqual(textView.enabledTextCheckingTypes & spelling, 0)

        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = true
        var updated = configuration
        updated.typography.fontSize = 18
        updated.apply(to: textView)
        XCTAssertFalse(textView.isContinuousSpellCheckingEnabled)
        XCTAssertTrue(textView.isGrammarCheckingEnabled)
        XCTAssertEqual(textView.font?.pointSize, 18)
    }

    func testSpellingMenuUsesTextViewActions() {
        let menu = SpellingMenu.makeSubmenu()
        XCTAssertEqual(menu.title, "Spelling and Grammar")
        XCTAssertEqual(menu.item(withTitle: "Show Spelling and Grammar")?.action, #selector(NSText.showGuessPanel(_:)))
        XCTAssertEqual(menu.item(withTitle: "Check Document Now")?.action, #selector(NSText.checkSpelling(_:)))
        XCTAssertEqual(
            menu.item(withTitle: "Check Spelling While Typing")?.action,
            #selector(NSTextView.toggleContinuousSpellChecking(_:))
        )
        XCTAssertEqual(
            menu.item(withTitle: "Check Grammar With Spelling")?.action,
            #selector(NSTextView.toggleGrammarChecking(_:))
        )
        XCTAssertEqual(
            menu.item(withTitle: "Correct Spelling Automatically")?.action,
            #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))
        )
        XCTAssertEqual(menu.item(withTitle: "Show Spelling and Grammar")?.keyEquivalent, ":")
        XCTAssertEqual(menu.item(withTitle: "Check Document Now")?.keyEquivalent, ";")
    }

    func testSpellingMenuInstallsOnceAfterSelectAll() {
        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        let main = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Find…", action: nil, keyEquivalent: "f")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main

        SpellingMenu.installIfNeeded()
        SpellingMenu.installIfNeeded()

        let installed = edit.items.filter { $0.title == "Spelling and Grammar" }
        XCTAssertEqual(installed.count, 1)
        let selectAll = edit.items.firstIndex { $0.action == #selector(NSText.selectAll(_:)) }
        let spelling = edit.items.firstIndex { $0.title == "Spelling and Grammar" }
        XCTAssertEqual(spelling, (selectAll ?? -1) + 2)
        XCTAssertNotNil(installed.first?.submenu?.item(withTitle: "Check Spelling While Typing"))
    }

    func testDelegateDropsMisspellingsInsideCode() {
        documentText = "misstake and `misstake`"
        let editor = MarkdownTextEditor(text: Binding(get: { self.documentText }, set: { self.documentText = $0 }))
        let coordinator = editor.makeCoordinator()
        let textView = MarkdownSourceTextView(usingTextLayoutManager: true)
        editor.configuration.apply(to: textView)
        editor.configuration.enableContinuousSpellChecking(on: textView)
        textView.delegate = coordinator
        textView.textStorage?.delegate = coordinator
        coordinator.textView = textView
        coordinator.replaceAll(documentText, in: textView)

        let storage = documentText as NSString
        let prose = storage.range(of: "misstake")
        let code = storage.range(
            of: "misstake",
            range: NSRange(location: prose.location + prose.length, length: storage.length - (prose.location + prose.length))
        )
        let results = [
            NSTextCheckingResult.spellCheckingResult(range: prose),
            NSTextCheckingResult.spellCheckingResult(range: code),
        ]
        let orthography = NSOrthography(dominantScript: "Latn", languageMap: ["Latn": ["en"]])
        let kept = coordinator.textView(
            textView,
            didCheckTextIn: NSRange(location: 0, length: storage.length),
            types: NSTextCheckingResult.CheckingType.spelling.rawValue,
            options: [NSSpellChecker.OptionKey: Any](),
            results: results,
            orthography: orthography,
            wordCount: 2
        )
        XCTAssertEqual(kept.map { $0.range }, [prose])
        let spellingFlag = NSAttributedString.SpellingState.spelling.rawValue
        XCTAssertEqual(coordinator.textView(textView, shouldSetSpellingState: spellingFlag, range: code), 0)
        XCTAssertEqual(coordinator.textView(textView, shouldSetSpellingState: spellingFlag, range: prose), spellingFlag)
        XCTAssertEqual(textView.spellingExclusions.isEmpty, false)
    }
}

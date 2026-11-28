import AppKit
import SwiftUI
import XCTest

@MainActor
final class SpellingTests: XCTestCase {
    private var documentText = ""
    private var retainedCoordinator: MarkdownTextEditor.Coordinator?

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

    func testSpellingMenuSurvivesTheRebuildWhenTheEditMenuOpens() {
        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        let main = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
        SpellingMenu.start()

        let delegate = RebuildingEditMenuDelegate()
        edit.delegate = delegate
        SpellingMenu.installIfNeeded()
        XCTAssertNotNil(edit.item(withTitle: "Spelling and Grammar"))

        edit.delegate?.menuNeedsUpdate?(edit)
        edit.delegate?.menuWillOpen?(edit)

        let installed = edit.items.filter { $0.title == "Spelling and Grammar" }
        XCTAssertEqual(installed.count, 1)
        XCTAssertEqual(delegate.rebuilds, 1)
        edit.delegate?.menuNeedsUpdate?(edit)
        XCTAssertEqual(edit.items.filter { $0.title == "Spelling and Grammar" }.count, 1)
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

    func testCheckDocumentNowSkipsCodeAndContextMenuOffersLearnAndIgnore() {
        let source = "`misstake` then misstake"
        let textView = makeWindowedEditor(source)
        defer { textView.window?.close() }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.checkSpelling(nil)

        let storage = source as NSString
        let first = storage.range(of: "misstake")
        let second = storage.range(
            of: "misstake",
            range: NSRange(location: first.location + first.length, length: storage.length - (first.location + first.length))
        )
        let full = NSRange(location: 0, length: storage.length)
        let spelling = NSTextCheckingResult.CheckingType.spelling.rawValue
        let raw = NSSpellChecker.shared.check(
            source,
            range: full,
            types: spelling,
            options: nil,
            inSpellDocumentWithTag: textView.spellCheckerDocumentTag,
            orthography: nil,
            wordCount: nil
        )
        XCTAssertTrue(raw.contains { NSIntersectionRange($0.range, first).length == first.length })
        XCTAssertEqual(textView.selectedRange(), second)

        textView.checkText(in: full, types: spelling, options: [:])
        let marked = waitForSpellingMarks(in: textView)
        XCTAssertTrue(marked.contains { NSIntersectionRange($0, second).length == second.length }, "marks \(marked)")
        XCTAssertFalse(marked.contains { NSIntersectionRange($0, first).length > 0 }, "marks \(marked)")

        guard let event = rightClick(in: textView, character: second.location) else {
            XCTFail("Could not build a right-click on the misspelling")
            return
        }
        let menu = textView.menu(for: event)
        let titles = menuItemTitles(in: menu)
        XCTAssertTrue(titles.contains("mistake"), "titles \(titles)")
        XCTAssertTrue(titles.contains("Learn Spelling"), "titles \(titles)")
        XCTAssertTrue(titles.contains("Ignore Spelling"), "titles \(titles)")
    }

    private func makeWindowedEditor(_ text: String) -> MarkdownSourceTextView {
        documentText = text
        let editor = MarkdownTextEditor(text: Binding(get: { self.documentText }, set: { self.documentText = $0 }))
        let coordinator = editor.makeCoordinator()
        let textView = MarkdownSourceTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        editor.configuration.apply(to: textView)
        editor.configuration.enableContinuousSpellChecking(on: textView)
        textView.delegate = coordinator
        textView.textStorage?.delegate = coordinator
        coordinator.textView = textView
        retainedCoordinator = coordinator
        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.documentView = textView
        let window = NSWindow(contentRect: scrollView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        window.orderFrontRegardless()
        _ = window.makeFirstResponder(textView)
        coordinator.replaceAll(text, in: textView)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        return textView
    }

    private func waitForSpellingMarks(in textView: NSTextView) -> [NSRange] {
        let deadline = Date().addingTimeInterval(2)
        var marked = spellingMarks(in: textView)
        while marked.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            marked = spellingMarks(in: textView)
        }
        return marked
    }

    private func spellingMarks(in textView: NSTextView) -> [NSRange] {
        var marks: [NSRange] = []
        if let layoutManager = textView.layoutManager {
            let length = (textView.string as NSString).length
            var index = 0
            while index < length {
                var range = NSRange(location: 0, length: 0)
                let value = layoutManager.temporaryAttribute(.spellingState, atCharacterIndex: index, effectiveRange: &range) as? NSNumber
                if let value, value.intValue != 0 { marks.append(range) }
                let next = NSMaxRange(range)
                index = next > index ? next : index + 1
            }
        }
        if let layoutManager = textView.textLayoutManager, let content = layoutManager.textContentManager {
            layoutManager.enumerateRenderingAttributes(from: content.documentRange.location, reverse: false) { _, attributes, textRange in
                let state = (attributes[.spellingState] as? NSNumber)?.intValue ?? 0
                if state != 0 { marks.append(utf16Range(textRange, in: content)) }
                return true
            }
        }
        return marks
    }

    private func utf16Range(_ textRange: NSTextRange, in content: NSTextContentManager) -> NSRange {
        let origin = content.documentRange.location
        let start = content.offset(from: origin, to: textRange.location)
        let end = content.offset(from: origin, to: textRange.endLocation)
        return NSRange(location: start, length: max(0, end - start))
    }

    private func rightClick(in textView: NSTextView, character index: Int) -> NSEvent? {
        guard let window = textView.window,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return nil }
        let glyph = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let bounds = layoutManager.boundingRect(forGlyphRange: glyph, in: textContainer)
        let origin = textView.textContainerOrigin
        let viewPoint = NSPoint(x: bounds.midX + origin.x, y: bounds.midY + origin.y)
        let location = textView.convert(viewPoint, to: nil)
        return NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
    }

    private func menuItemTitles(in menu: NSMenu?) -> [String] {
        guard let menu else { return [] }
        var titles: [String] = []
        for item in menu.items {
            titles.append(item.title)
            titles.append(contentsOf: menuItemTitles(in: item.submenu))
        }
        return titles
    }
}

private final class RebuildingEditMenuDelegate: NSObject, NSMenuDelegate {
    private(set) var rebuilds = 0

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuilds += 1
        guard rebuilds == 1 else { return }
        let selectAll = menu.item(withTitle: "Select All")
            ?? NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.removeAllItems()
        menu.addItem(selectAll)
    }
}

#if os(macOS)
import AppKit

@MainActor
enum SpellingMenu {
    private static var isObservingMenuTracking = false

    static func start() {
        if !isObservingMenuTracking {
            isObservingMenuTracking = true
            NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    installIfNeeded()
                }
            }
        }
        installIfNeeded()
    }

    static func installIfNeeded() {
        guard let edit = editMenu() else { return }
        if edit.items.contains(where: { $0.title == menuTitle }) { return }
        let item = NSMenuItem(title: menuTitle, action: nil, keyEquivalent: "")
        item.submenu = makeSubmenu()
        guard let selectAll = edit.items.firstIndex(where: { $0.action == #selector(NSText.selectAll(_:)) }) else {
            edit.addItem(.separator())
            edit.addItem(item)
            return
        }
        let insertion = selectAll + 1
        edit.insertItem(.separator(), at: insertion)
        edit.insertItem(item, at: insertion + 1)
    }

    static func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: menuTitle)
        let showPanel = menu.addItem(
            withTitle: "Show Spelling and Grammar",
            action: #selector(NSText.showGuessPanel(_:)),
            keyEquivalent: ":"
        )
        showPanel.keyEquivalentModifierMask = .command
        let checkDocument = menu.addItem(
            withTitle: "Check Document Now",
            action: #selector(NSText.checkSpelling(_:)),
            keyEquivalent: ";"
        )
        checkDocument.keyEquivalentModifierMask = .command
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Check Spelling While Typing",
            action: #selector(NSTextView.toggleContinuousSpellChecking(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Check Grammar With Spelling",
            action: #selector(NSTextView.toggleGrammarChecking(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Correct Spelling Automatically",
            action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)),
            keyEquivalent: ""
        )
        return menu
    }

    private static let menuTitle = "Spelling and Grammar"

    private static func editMenu() -> NSMenu? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            if submenu.items.contains(where: { $0.action == #selector(NSText.selectAll(_:)) }) { return submenu }
        }
        return mainMenu.item(withTitle: "Edit")?.submenu
    }
}
#endif

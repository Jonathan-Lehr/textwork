#if os(macOS)
import AppKit
import ObjectiveC

@MainActor
enum SpellingMenu {
    nonisolated(unsafe) private static var wrapsDelegates = false
    nonisolated(unsafe) private static var isInstalling = false
    nonisolated(unsafe) private static let proxies = NSMapTable<NSMenu, SpellingMenuDelegate>.weakToStrongObjects()

    static func start() {
        installDelegateHook()
        wrapsDelegates = true
        guard let mainMenu = NSApp.mainMenu else { return }
        prepare(mainMenu)
        for item in mainMenu.items {
            if let submenu = item.submenu { prepare(submenu) }
        }
    }

    /// SwiftUI refills the Edit menu in its delegate the first time a document is key.
    /// That refill runs after tracking begins and drops anything inserted earlier, so the
    /// item has to be added again once the delegate has finished and before the menu is shown.
    static func installIfNeeded() {
        if isInstalling { return }
        isInstalling = true
        defer { isInstalling = false }
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

    nonisolated fileprivate static func delegateToInstall(on menu: NSMenu, requested: NSMenuDelegate?) -> NSMenuDelegate? {
        guard wrapsDelegates, let requested, !(requested is SpellingMenuDelegate) else {
            if requested == nil { proxies.removeObject(forKey: menu) }
            return requested
        }
        return proxy(forwarding: requested, for: menu)
    }

    private static func prepare(_ menu: NSMenu) {
        if menu.delegate is SpellingMenuDelegate { return }
        menu.delegate = proxy(forwarding: menu.delegate, for: menu)
    }

    nonisolated private static func proxy(forwarding: NSMenuDelegate?, for menu: NSMenu) -> SpellingMenuDelegate {
        let proxy = SpellingMenuDelegate(forwarding: forwarding)
        proxies.setObject(proxy, forKey: menu)
        return proxy
    }

    private static func installDelegateHook() {
        guard !wrapsDelegates else { return }
        let selector = #selector(setter: NSMenu.delegate)
        guard let method = class_getInstanceMethod(NSMenu.self, selector) else { return }
        let original = method_getImplementation(method)
        let block: @convention(block) (NSMenu, NSMenuDelegate?) -> Void = { menu, delegate in
            let installed = delegateToInstall(on: menu, requested: delegate)
            unsafeBitCast(original, to: DelegateSetter.self)(menu, selector, installed)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
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

private typealias DelegateSetter = @convention(c) (NSMenu, Selector, NSMenuDelegate?) -> Void

private final class SpellingMenuDelegate: NSObject, NSMenuDelegate {
    let forwarding: NSMenuDelegate?

    init(forwarding: NSMenuDelegate?) {
        self.forwarding = forwarding
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        forwarding?.menuNeedsUpdate?(menu)
        SpellingMenu.installIfNeeded()
    }

    func menuWillOpen(_ menu: NSMenu) {
        forwarding?.menuWillOpen?(menu)
        SpellingMenu.installIfNeeded()
    }

    override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        return forwarding?.responds(to: selector) ?? false
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if super.responds(to: selector) { return nil }
        return forwarding
    }
}
#endif

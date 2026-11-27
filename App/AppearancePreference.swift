import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Light, dark, or the system appearance. Automatic is the default.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case light
    case dark
    case automatic = "system"

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .automatic: "Automatic"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .automatic: nil
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AppearancePreference {
        guard let rawValue = defaults.string(forKey: storageKey) else { return .automatic }
        return AppearancePreference(rawValue: rawValue) ?? .automatic
    }
}

#if os(macOS)
@MainActor
extension AppearancePreference {
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .automatic: nil
        }
    }

    func applyToApplication() {
        NSApp.appearance = nsAppearance
    }
}
#endif

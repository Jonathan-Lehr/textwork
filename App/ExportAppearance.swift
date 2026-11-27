import Foundation
import TextworkEditor

/// How exported HTML, PDF, and print choose light or dark.
///
/// Light is the default. Follow Appearance uses the app setting, and a
/// concrete export resolves Automatic to the appearance on screen.
enum ExportAppearance: String, CaseIterable, Identifiable {
    case light
    case followApplication

    static let storageKey = "exportAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .followApplication: "Follow Appearance"
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> ExportAppearance {
        guard let rawValue = defaults.string(forKey: storageKey) else { return .light }
        return ExportAppearance(rawValue: rawValue) ?? .light
    }

    /// `concrete` is for PDF and print, which have to pick one palette.
    /// HTML can stay automatic and follow the viewer.
    func htmlColorScheme(
        applicationAppearance: AppearancePreference,
        systemIsDark: Bool,
        concrete: Bool
    ) -> MarkdownHTMLColorScheme {
        switch self {
        case .light: return .light
        case .followApplication:
            switch applicationAppearance {
            case .light: return .light
            case .dark: return .dark
            case .automatic:
                if !concrete { return .automatic }
                return systemIsDark ? .dark : .light
            }
        }
    }
}

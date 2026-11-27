import AppKit
import SwiftUI
import XCTest

@MainActor
final class AppearancePreferenceTests: XCTestCase {
    func testValueMapsToAppearance() {
        XCTAssertEqual(AppearancePreference.light.rawValue, "light")
        XCTAssertEqual(AppearancePreference.dark.rawValue, "dark")
        XCTAssertEqual(AppearancePreference.automatic.rawValue, "system")

        XCTAssertEqual(AppearancePreference.light.colorScheme, .light)
        XCTAssertEqual(AppearancePreference.dark.colorScheme, .dark)
        XCTAssertNil(AppearancePreference.automatic.colorScheme)

        XCTAssertEqual(AppearancePreference.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppearancePreference.dark.nsAppearance?.name, .darkAqua)
        XCTAssertNil(AppearancePreference.automatic.nsAppearance)
    }
}

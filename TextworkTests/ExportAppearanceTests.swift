import XCTest
import TextworkEditor

final class ExportAppearanceTests: XCTestCase {
    func testExportDefaultsToLightAndCanFollowTheApp() {
        let suiteName = "ExportAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(ExportAppearance.stored(in: defaults), .light)
        defaults.set("sepia", forKey: ExportAppearance.storageKey)
        XCTAssertEqual(ExportAppearance.stored(in: defaults), .light)

        let light = ExportAppearance.light
        XCTAssertEqual(
            light.htmlColorScheme(applicationAppearance: .dark, systemIsDark: true, concrete: true),
            .light
        )
        XCTAssertEqual(
            light.htmlColorScheme(applicationAppearance: .automatic, systemIsDark: true, concrete: false),
            .light
        )

        let follow = ExportAppearance.followApplication
        XCTAssertEqual(
            follow.htmlColorScheme(applicationAppearance: .dark, systemIsDark: false, concrete: true),
            .dark
        )
        XCTAssertEqual(
            follow.htmlColorScheme(applicationAppearance: .light, systemIsDark: true, concrete: false),
            .light
        )
        XCTAssertEqual(
            follow.htmlColorScheme(applicationAppearance: .automatic, systemIsDark: true, concrete: false),
            .automatic
        )
        XCTAssertEqual(
            follow.htmlColorScheme(applicationAppearance: .automatic, systemIsDark: true, concrete: true),
            .dark
        )
        XCTAssertEqual(
            follow.htmlColorScheme(applicationAppearance: .automatic, systemIsDark: false, concrete: true),
            .light
        )
    }

    func testPageBreaksIgnoreAFractionalPoint() {
        XCTAssertEqual(DocumentHTMLPresenter.pageCount(documentHeight: 0, pageHeight: 792), 1)
        XCTAssertEqual(DocumentHTMLPresenter.pageCount(documentHeight: 100, pageHeight: 792), 1)
        XCTAssertEqual(DocumentHTMLPresenter.pageCount(documentHeight: 792, pageHeight: 792), 1)
        XCTAssertEqual(DocumentHTMLPresenter.pageCount(documentHeight: 792.4, pageHeight: 792), 1)
        XCTAssertEqual(DocumentHTMLPresenter.pageCount(documentHeight: 800, pageHeight: 792), 2)
        XCTAssertEqual(DocumentHTMLPresenter.pageCount(documentHeight: 1584, pageHeight: 792), 2)
    }
}

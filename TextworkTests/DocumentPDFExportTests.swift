import AppKit
import PDFKit
import TextworkEditor
import XCTest

@MainActor
final class DocumentPDFExportTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        let application = NSApplication.shared
        if application.activationPolicy() != .accessory { application.setActivationPolicy(.accessory) }
        if !application.isRunning { application.finishLaunching() }
    }

    func testLongDocumentExportsMoreThanOnePage() async throws {
        let paragraph = "The quick brown fox jumps over the lazy dog and keeps this line long enough to wrap.\n\n"
        let markdown = String(repeating: paragraph, count: 80)
        let html = MarkdownHTMLRenderer().renderDocument(markdown, title: "Pages", colorScheme: .light)
        let data = try await DocumentHTMLPresenter().pdfDocumentData(html: html, baseURL: nil, colorScheme: .light)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        let paper = NSPrintInfo.shared.paperSize
        XCTAssertGreaterThan(document.pageCount, 1)
        let first = try XCTUnwrap(document.page(at: 0))
        let bounds = first.bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, paper.width, accuracy: 1)
        XCTAssertEqual(bounds.height, paper.height, accuracy: 1)
    }
}

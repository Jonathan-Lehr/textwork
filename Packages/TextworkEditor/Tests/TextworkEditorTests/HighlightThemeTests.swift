import XCTest
@testable import TextworkEditor
#if canImport(AppKit)
import AppKit
#endif

final class HighlightThemeTests: XCTestCase {
    private let theme = HighlightTheme.standard
    private let highlighter = MarkdownHighlighter()

    func testRoleToColorMapping() {
        let expected: [HighlightRole: ExpectedColors] = [
            .heading1: ExpectedColors("#1D1D1F", "#F5F5F7", "#5D72B0", "#7786BD"),
            .heading2: ExpectedColors("#1D1D1F", "#F5F5F7", "#5D72B0", "#7786BD"),
            .heading3: ExpectedColors("#1D1D1F", "#F5F5F7", "#5D72B0", "#7786BD"),
            .heading4: ExpectedColors("#1D1D1F", "#F5F5F7", "#5D72B0", "#7786BD"),
            .heading5: ExpectedColors("#1D1D1F", "#F5F5F7", "#5D72B0", "#7786BD"),
            .heading6: ExpectedColors("#1D1D1F", "#F5F5F7", "#5D72B0", "#7786BD"),
            .emphasis: ExpectedColors("#1D1D1F", "#F5F5F7", "#6E6E73", "#98989D"),
            .strong: ExpectedColors("#1D1D1F", "#F5F5F7", "#6E6E73", "#98989D"),
            .codeSpan: ExpectedColors("#A8284A", "#FFA0B8", "#B9516C", "#B67686"),
            .codeBlock: ExpectedColors("#A8284A", "#FFA0B8", "#B9516C", "#B67686"),
            .codeKeyword: ExpectedColors("#1A4FC4", "#8EB4FF", "#4670CF", "#6E88BE"),
            .codeString: ExpectedColors("#146228", "#86D996", "#438153", "#60946A"),
            .codeNumber: ExpectedColors("#8A4E00", "#F0B45C", "#9C6926", "#A98147"),
            .codeComment: ExpectedColors("#5A5A60", "#A3A3A8", "#737378", "#88888C"),
            .codeType: ExpectedColors("#0E6F86", "#79D0E4", "#267D92", "#58909D"),
            .codeTag: ExpectedColors("#7A2F8A", "#E0A0EC", "#975DA4", "#A679AE"),
            .codeAttribute: ExpectedColors("#9A4E12", "#F0B07A", "#A6632E", "#AB805C"),
            .link: ExpectedColors("#0066CC", "#419CFF", "#1C77D2", "#3C8ADF"),
            .image: ExpectedColors("#086E68", "#78E0D6", "#27807B", "#54938D"),
            .listMarker: ExpectedColors("#3A4A78", "#BAC6E8", "#667396", "#80889D"),
            .blockQuote: ExpectedColors("#40603A", "#C6D8B0", "#607B5B", "#818C74"),
            .thematicBreak: ExpectedColors("#3A3A3E", "#D2D2D6", "#737376", "#88888B"),
            .table: ExpectedColors("#1D1D1F", "#F5F5F7", "#747475", "#888889"),
            .html: ExpectedColors("#0C6A32", "#8CDCA0", "#338253", "#62936E"),
        ]
        XCTAssertEqual(Set(expected.keys), Set(HighlightRole.allCases))
        for role in HighlightRole.allCases {
            let colors = expected[role]!
            let content = theme.color(for: role, isSyntax: false)
            let syntax = theme.color(for: role, isSyntax: true)
            XCTAssertEqual(content.light.cssHex, colors.contentLight, role.rawValue)
            XCTAssertEqual(content.dark.cssHex, colors.contentDark, role.rawValue)
            XCTAssertEqual(syntax.light.cssHex, colors.syntaxLight, role.rawValue)
            XCTAssertEqual(syntax.dark.cssHex, colors.syntaxDark, role.rawValue)
            XCTAssertNotEqual(content.light, content.dark, role.rawValue)
            XCTAssertNotEqual(syntax.light, syntax.dark, role.rawValue)
            XCTAssertNotEqual(content, syntax, role.rawValue)
            if role == .codeSpan {
                XCTAssertEqual(theme.backgroundColor(for: role, isSyntax: false), theme.inlineCodeBackground)
                XCTAssertNil(theme.backgroundColor(for: role, isSyntax: true), role.rawValue)
            } else {
                XCTAssertNil(theme.backgroundColor(for: role, isSyntax: false), role.rawValue)
                XCTAssertNil(theme.backgroundColor(for: role, isSyntax: true), role.rawValue)
            }
        }
        XCTAssertEqual(theme.body.light.cssHex, "#1D1D1F")
        XCTAssertEqual(theme.body.dark.cssHex, "#F5F5F7")
    }

    func testSyntaxMarkersAreSubtlerThanContent() {
        let lightBackground = HighlightTheme.lightEditorBackground
        let darkBackground = HighlightTheme.darkEditorBackground
        for role in HighlightRole.allCases {
            let content = theme.color(for: role, isSyntax: false)
            let syntax = theme.color(for: role, isSyntax: true)
            let contentLight = contrast(content.light, lightBackground)
            let syntaxLight = contrast(syntax.light, lightBackground)
            let contentDark = contrast(content.dark, darkBackground)
            let syntaxDark = contrast(syntax.dark, darkBackground)
            XCTAssertGreaterThanOrEqual(contentLight, 4.5, "\(role.rawValue) light content")
            XCTAssertGreaterThanOrEqual(contentDark, 4.5, "\(role.rawValue) dark content")
            XCTAssertGreaterThanOrEqual(syntaxLight, 4.4, "\(role.rawValue) light syntax")
            XCTAssertGreaterThanOrEqual(syntaxDark, 4.4, "\(role.rawValue) dark syntax")
            XCTAssertGreaterThan(contentLight, syntaxLight + 0.9, "\(role.rawValue) light")
            XCTAssertGreaterThan(contentDark, syntaxDark + 0.9, "\(role.rawValue) dark")
        }
    }

    func testRunStyleUsesForegroundAndFontWithoutAFill() {
        for role in HighlightRole.allCases {
            for isSyntax in [false, true] {
                let style = theme.runStyle(for: role, isSyntax: isSyntax)
                XCTAssertEqual(style.foreground, theme.color(for: role, isSyntax: isSyntax))
                let expectsFill = role == .codeSpan && !isSyntax
                if expectsFill {
                    XCTAssertEqual(style.background, theme.inlineCodeBackground)
                } else {
                    XCTAssertNil(style.background)
                }
            }
        }
        XCTAssertEqual(theme.color(for: .heading1, isSyntax: false), theme.body)
        XCTAssertEqual(theme.color(for: .emphasis, isSyntax: false), theme.body)
        XCTAssertEqual(theme.color(for: .strong, isSyntax: false), theme.body)
        XCTAssertEqual(theme.color(for: .heading1, isSyntax: true).light.cssHex, "#5D72B0")
        XCTAssertNotEqual(theme.color(for: .emphasis, isSyntax: true), theme.color(for: .emphasis, isSyntax: false))
        XCTAssertEqual(theme.inlineCodeBackground.light.cssHex, "#F3F3F5")
        XCTAssertEqual(theme.inlineCodeBackground.dark.cssHex, "#2A2A2E")
        let code = theme.color(for: .codeSpan, isSyntax: false)
        XCTAssertGreaterThanOrEqual(contrast(code.light, theme.inlineCodeBackground.light), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(code.dark, theme.inlineCodeBackground.dark), 4.5)

        XCTAssertEqual(theme.runStyle(for: .codeSpan, isSyntax: false).fontTreatment, .monospaced)
        XCTAssertEqual(theme.runStyle(for: .codeSpan, isSyntax: true).fontTreatment, .monospaced)
        XCTAssertEqual(theme.runStyle(for: .codeBlock, isSyntax: false).fontTreatment, .monospaced)
        XCTAssertEqual(theme.runStyle(for: .codeBlock, isSyntax: true).fontTreatment, .monospaced)
        XCTAssertEqual(theme.runStyle(for: .html, isSyntax: false).fontTreatment, .monospaced)
        XCTAssertEqual(theme.runStyle(for: .html, isSyntax: true).fontTreatment, .body)
        XCTAssertEqual(theme.runStyle(for: .heading1, isSyntax: false).fontTreatment, .heading)
        XCTAssertEqual(theme.runStyle(for: .heading1, isSyntax: true).fontTreatment, .body)
        XCTAssertEqual(theme.runStyle(for: .emphasis, isSyntax: false).fontTreatment, .emphasis)
        XCTAssertEqual(theme.runStyle(for: .strong, isSyntax: false).fontTreatment, .strong)
        XCTAssertTrue(theme.runStyle(for: .link, isSyntax: false).underline)
        XCTAssertFalse(theme.runStyle(for: .link, isSyntax: true).underline)
        XCTAssertTrue(theme.runStyle(for: .image, isSyntax: false).underline)
        XCTAssertFalse(theme.runStyle(for: .image, isSyntax: true).underline)
        XCTAssertEqual(theme.runStyle(for: .listMarker, isSyntax: true).fontTreatment, .body)
        XCTAssertEqual(theme.runStyle(for: .blockQuote, isSyntax: true).fontTreatment, .body)
    }

    func testHeadingsShareAColorAndCodeDoesNotDependOnLanguage() {
        for role in [HighlightRole.heading2, .heading3, .heading4, .heading5, .heading6] {
            XCTAssertEqual(theme.colors(for: role), theme.colors(for: .heading1))
        }
        XCTAssertEqual(theme.colors(for: .codeSpan), theme.colors(for: .codeBlock))
        XCTAssertNotEqual(theme.color(for: .heading1, isSyntax: false), theme.color(for: .link, isSyntax: false))

        let fences = [
            "```swift\nlet answer = 42\n```",
            "```python\nanswer = 42\n```",
            "```\nanswer = 42\n```",
        ]
        let codeColors: Set<HighlightColor> = [
            theme.color(for: .codeBlock, isSyntax: false),
            theme.color(for: .codeBlock, isSyntax: true),
        ]
        for source in fences {
            let colors = Set(highlighter.highlight(source).spans.filter { $0.role == .codeBlock }.map {
                theme.color(for: $0.role, isSyntax: $0.isSyntax)
            })
            XCTAssertEqual(colors, codeColors, source)
        }
        let indented = Set(highlighter.highlight("    indented\n").spans.filter { $0.role == .codeBlock }.map {
            theme.color(for: $0.role, isSyntax: $0.isSyntax)
        })
        XCTAssertEqual(indented, [theme.color(for: .codeBlock, isSyntax: false)])
    }

    func testReferenceLinksUseTheLinkColors() {
        let source = """
        [example]: https://example.com "Title"

        See [text][example], [example], and ![Alt][example].
        """
        let spans = highlighter.highlight(source).spans
        let links = spans.filter { $0.role == .link }
        XCTAssertTrue(links.contains { $0.isSyntax })
        XCTAssertTrue(links.contains { !$0.isSyntax })
        for span in links {
            XCTAssertEqual(
                theme.color(for: span.role, isSyntax: span.isSyntax),
                theme.color(for: .link, isSyntax: span.isSyntax)
            )
        }
        XCTAssertEqual(theme.color(for: .link, isSyntax: false).light.cssHex, "#0066CC")
        XCTAssertFalse(spans.filter { $0.role == .image }.isEmpty)
    }

    func testPreviewStylesheetUsesTheThemeAndPrefersColorScheme() {
        let stylesheet = MarkdownHTMLRenderer.stylesheet
        guard let media = stylesheet.range(of: "@media (prefers-color-scheme: dark)") else {
            XCTFail("Missing prefers-color-scheme")
            return
        }
        let light = stylesheet[..<media.lowerBound]
        let dark = stylesheet[media.lowerBound...]
        let shown: [HighlightRole] = [.heading1, .emphasis, .strong, .codeSpan, .link, .blockQuote]
        for role in shown {
            let color = theme.color(for: role, isSyntax: false)
            XCTAssertTrue(light.contains(color.light.cssHex), role.rawValue)
            XCTAssertTrue(dark.contains(color.dark.cssHex), role.rawValue)
            XCTAssertFalse(light.contains(color.dark.cssHex), role.rawValue)
        }
        let quoteMarker = theme.color(for: .blockQuote, isSyntax: true)
        let listMarker = theme.color(for: .listMarker, isSyntax: true)
        let thematic = theme.color(for: .thematicBreak, isSyntax: true)
        XCTAssertTrue(light.contains(quoteMarker.light.cssHex))
        XCTAssertTrue(light.contains(listMarker.light.cssHex))
        XCTAssertTrue(light.contains(thematic.light.cssHex))
        XCTAssertTrue(dark.contains(quoteMarker.dark.cssHex))
        XCTAssertTrue(stylesheet.contains("background: var(--code-fill)"))
        XCTAssertTrue(stylesheet.contains(theme.inlineCodeBackground.light.cssHex))
        XCTAssertTrue(stylesheet.contains(theme.inlineCodeBackground.dark.cssHex))
        XCTAssertFalse(stylesheet.contains("em { color"))
        XCTAssertFalse(stylesheet.contains("strong { color"))
        XCTAssertFalse(stylesheet.contains("color: var(--heading)"))
        XCTAssertTrue(stylesheet.contains("h1 { font-size: 2rem;"))
        XCTAssertTrue(stylesheet.contains("h2 { font-size: 1.55rem;"))
        if let preStart = stylesheet.range(of: "pre {") {
            let afterPre = stylesheet[preStart.upperBound...]
            if let preEnd = afterPre.range(of: "}") {
                XCTAssertFalse(stylesheet[preStart.lowerBound..<preEnd.upperBound].contains("background"))
            } else {
                XCTFail("Unclosed pre rule")
            }
        } else {
            XCTFail("Missing pre rule")
        }
        XCTAssertTrue(stylesheet.contains("padding: 0.12em 0.35em"))
        XCTAssertTrue(stylesheet.contains("width: min(68ch, 100%)"))
        XCTAssertTrue(stylesheet.contains("h1 { font-size: 2rem;"))
        XCTAssertFalse(stylesheet.contains("language-"))
        XCTAssertTrue(stylesheet.contains("color-scheme: light dark"))
    }

    #if canImport(AppKit)
    func testPlatformColorFollowsAppearance() {
        let appearances: [(NSAppearance.Name, KeyPath<HighlightColor, HighlightColorComponents>)] = [
            (.aqua, \.light),
            (.darkAqua, \.dark),
        ]
        for role in HighlightRole.allCases {
            for isSyntax in [false, true] {
                let source = theme.color(for: role, isSyntax: isSyntax)
                let platform = theme.platformColor(for: role, isSyntax: isSyntax)
                for (name, component) in appearances {
                    let expected = source[keyPath: component]
                    let resolved = resolvedColor(platform, appearance: name)
                    XCTAssertEqual(resolved.redComponent, CGFloat(expected.unitRed), accuracy: 0.004, "\(role) \(name.rawValue)")
                    XCTAssertEqual(resolved.greenComponent, CGFloat(expected.unitGreen), accuracy: 0.004, "\(role) \(name.rawValue)")
                    XCTAssertEqual(resolved.blueComponent, CGFloat(expected.unitBlue), accuracy: 0.004, "\(role) \(name.rawValue)")
                }
            }
        }
        let body = resolvedColor(theme.bodyPlatformColor, appearance: .aqua)
        XCTAssertEqual(body.redComponent, CGFloat(theme.body.light.unitRed), accuracy: 0.004)
    }

    func testForegroundColorDrawsInLightAndDark() {
        let draw = {
            let source = self.theme.color(for: .codeSpan, isSyntax: false)
            let color = self.theme.platformColor(source)
            self.assertDrawn(
                color: color,
                expected: source.light,
                appearance: .aqua,
                background: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            )
            self.assertDrawn(
                color: color,
                expected: source.dark,
                appearance: .darkAqua,
                background: NSColor(srgbRed: 30.0 / 255, green: 30.0 / 255, blue: 30.0 / 255, alpha: 1)
            )
            let syntax = self.theme.color(for: .heading1, isSyntax: true)
            self.assertDrawn(
                color: self.theme.platformColor(syntax),
                expected: syntax.light,
                appearance: .aqua,
                background: NSColor.white
            )
        }
        if Thread.isMainThread {
            draw()
        } else {
            DispatchQueue.main.sync(execute: draw)
        }
    }

    @MainActor
    func testWriteThemeSnapshotsWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["TEXTWORK_THEME_SNAPSHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let light = NSAppearance.Name.aqua
        let dark = NSAppearance.Name.darkAqua
        writeSnapshot(named: "editor_before_light.png", appearance: light, previousPaint: true, to: directory)
        writeSnapshot(named: "editor_after_light.png", appearance: light, previousPaint: false, to: directory)
        writeSnapshot(named: "editor_after_dark.png", appearance: dark, previousPaint: false, to: directory)
        for name in ["editor_before_light.png", "editor_after_light.png", "editor_after_dark.png"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 1000, name)
        }
    }

    private func resolvedColor(_ color: NSColor, appearance name: NSAppearance.Name) -> NSColor {
        var resolved = color
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private func assertDrawn(
        color: NSColor,
        expected: HighlightColorComponents,
        appearance: NSAppearance.Name,
        background: NSColor
    ) {
        let width = 280
        let height = 90
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("No bitmap")
            return
        }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            background.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            let context = NSGraphicsContext.current?.cgContext
            context?.setShouldAntialias(false)
            context?.setAllowsAntialiasing(false)
            context?.setShouldSmoothFonts(false)
            let sample = NSAttributedString(
                string: "Code",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 56, weight: .regular),
                    .foregroundColor: color,
                ]
            )
            sample.draw(at: NSPoint(x: 8, y: 12))
        }
        NSGraphicsContext.restoreGraphicsState()

        let backgroundBytes = bytes(of: background)
        var best = Int.max
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let red = Int((pixel.redComponent * 255).rounded())
                let green = Int((pixel.greenComponent * 255).rounded())
                let blue = Int((pixel.blueComponent * 255).rounded())
                if channelDistance(red, green, blue, backgroundBytes) < 18 { continue }
                let gap = channelDistance(red, green, blue, (Int(expected.red), Int(expected.green), Int(expected.blue)))
                if gap < best { best = gap }
            }
        }
        XCTAssertLessThan(best, 24, "\(appearance.rawValue) drew \(expected.cssHex) at distance \(best)")
    }

    private func bytes(of color: NSColor) -> (Int, Int, Int) {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        return (
            Int((resolved.redComponent * 255).rounded()),
            Int((resolved.greenComponent * 255).rounded()),
            Int((resolved.blueComponent * 255).rounded())
        )
    }

    private func channelDistance(_ red: Int, _ green: Int, _ blue: Int, _ other: (Int, Int, Int)) -> Int {
        abs(red - other.0) + abs(green - other.1) + abs(blue - other.2)
    }

    @MainActor
    private func writeSnapshot(named name: String, appearance: NSAppearance.Name, previousPaint: Bool, to directory: String) {
        let text = snapshotDocument
        let width: CGFloat = 680
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 1600)
        textView.isRichText = true
        textView.drawsBackground = true
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 18, height: 16)
        let drawingAppearance = NSAppearance(named: appearance)
        textView.appearance = drawingAppearance
        if appearance == .darkAqua {
            textView.backgroundColor = NSColor(srgbRed: 30.0 / 255, green: 30.0 / 255, blue: 30.0 / 255, alpha: 1)
        } else {
            textView.backgroundColor = NSColor.white
        }
        textView.string = text
        let storage = textView.textStorage!
        if previousPaint {
            paintPreviousEditor(storage, text: text)
        } else {
            paintThemedEditor(storage, text: text)
        }
        guard let layoutManager = textView.textLayoutManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let used = layoutManager.usageBoundsForTextContainer
        let height = max(240, ceil(used.height) + textView.textContainerInset.height * 2 + 8)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        let window = NSWindow(
            contentRect: textView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = drawingAppearance
        window.contentView = textView
        window.orderFrontRegardless()
        textView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else { return }
        textView.cacheDisplay(in: textView.bounds, to: rep)
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    private func paintThemedEditor(_ storage: NSTextStorage, text: String) {
        let fontSize: CGFloat = 16
        let body = NSFont.systemFont(ofSize: fontSize)
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        storage.setAttributes(
            [.font: body, .foregroundColor: theme.bodyPlatformColor],
            range: NSRange(location: 0, length: storage.length)
        )
        let spans = highlighter.highlight(text).spans
        for span in spans where !span.isSyntax {
            paint(span, body: body, mono: mono, fontSize: fontSize, storage: storage)
        }
        for span in spans where span.isSyntax {
            paint(span, body: body, mono: mono, fontSize: fontSize, storage: storage)
        }
    }

    private func paint(
        _ span: HighlightSpan,
        body: NSFont,
        mono: NSFont,
        fontSize: CGFloat,
        storage: NSTextStorage
    ) {
        let range = NSRange(location: span.startUTF16, length: span.endUTF16 - span.startUTF16)
        guard range.location + range.length <= storage.length, range.length > 0 else { return }
        let style = theme.runStyle(for: span.role, isSyntax: span.isSyntax)
        var font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? body
        let manager = NSFontManager.shared
        switch style.fontTreatment {
        case .body:
            font = body
        case .monospaced:
            font = mono
        case .heading:
            let boost: CGFloat
            switch span.role {
            case .heading1: boost = 8
            case .heading2: boost = 5
            default: boost = 2
            }
            font = manager.convert(NSFont.systemFont(ofSize: fontSize + boost), toHaveTrait: .boldFontMask)
        case .emphasis:
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        case .strong:
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        storage.addAttribute(.font, value: font, range: range)
        storage.addAttribute(.foregroundColor, value: theme.platformColor(style.foreground), range: range)
        if style.underline {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    /// The editor before this theme: font changes, a gray code fill, link blue, and teal HTML.
    private func paintPreviousEditor(_ storage: NSTextStorage, text: String) {
        let fontSize: CGFloat = 16
        let body = NSFont.systemFont(ofSize: fontSize)
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let manager = NSFontManager.shared
        storage.setAttributes(
            [.font: body, .foregroundColor: NSColor.labelColor],
            range: NSRange(location: 0, length: storage.length)
        )
        let spans = highlighter.highlight(text).spans
        func range(of span: HighlightSpan) -> NSRange? {
            let result = NSRange(location: span.startUTF16, length: span.endUTF16 - span.startUTF16)
            guard result.location + result.length <= storage.length, result.length > 0 else { return nil }
            return result
        }
        for span in spans where !span.isSyntax {
            guard let range = range(of: span) else { continue }
            var font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? body
            switch span.role {
            case .heading1:
                font = manager.convert(NSFont.systemFont(ofSize: fontSize + 8), toHaveTrait: .boldFontMask)
            case .heading2, .heading3, .heading4, .heading5, .heading6:
                font = manager.convert(NSFont.systemFont(ofSize: fontSize + 3), toHaveTrait: .boldFontMask)
            case .emphasis:
                font = manager.convert(font, toHaveTrait: .italicFontMask)
            case .strong:
                font = manager.convert(font, toHaveTrait: .boldFontMask)
            case .codeSpan, .codeBlock:
                font = mono
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.quaternaryLabelColor.withAlphaComponent(0.35),
                    range: range
                )
            case .link, .image:
                storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .html:
                font = mono
                storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: range)
            case .table, .listMarker, .blockQuote, .thematicBreak, .codeKeyword, .codeString, .codeNumber, .codeComment, .codeType, .codeTag, .codeAttribute:
                break
            }
            storage.addAttribute(.font, value: font, range: range)
        }
        for span in spans where span.isSyntax {
            guard let range = range(of: span) else { continue }
            storage.addAttributes(
                [.font: body, .foregroundColor: NSColor.tertiaryLabelColor],
                range: range
            )
        }
    }
    #endif
}

private struct ExpectedColors {
    var contentLight: String
    var contentDark: String
    var syntaxLight: String
    var syntaxDark: String

    init(_ contentLight: String, _ contentDark: String, _ syntaxLight: String, _ syntaxDark: String) {
        self.contentLight = contentLight
        self.contentDark = contentDark
        self.syntaxLight = syntaxLight
        self.syntaxDark = syntaxDark
    }
}

private func relativeLuminance(_ components: HighlightColorComponents) -> Double {
    func channel(_ byte: UInt8) -> Double {
        let value = Double(byte) / 255
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(components.red) + 0.7152 * channel(components.green) + 0.0722 * channel(components.blue)
}

private func contrast(_ first: HighlightColorComponents, _ second: HighlightColorComponents) -> Double {
    let lighter = max(relativeLuminance(first), relativeLuminance(second))
    let darker = min(relativeLuminance(first), relativeLuminance(second))
    return (lighter + 0.05) / (darker + 0.05)
}

private let snapshotDocument = """
# Textwork

A paragraph with *emphasis*, **strong**, and `inline code`.

## Links and lists

- List item
- [Link](https://example.com) and a [reference][example]

> Block quotes stay in the source.

---

| Syntax | Shown |
| --- | --- |
| raw | live |

```
fenced code
```

Use <em>html</em> in the source.

![Alt](images/figure.png)

[example]: https://example.com
"""

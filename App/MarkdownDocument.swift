import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.textworkMarkdown] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }

    /// Sample opened from the Help menu. New documents stay empty.
    static let markdownGuide = """
    # Textwork

    A plain-text Markdown editor. The card on the side is a read-only preview.

    Write with *emphasis*, **strong**, and `inline code`.

    - Lists keep their markers
    - [Links](https://example.com) stay in the source
    - Images use a path relative to the file: ![Alt](images/figure.png)

    > Block quotes are still just text.

    | Syntax | Shown |
    | --- | --- |
    | raw | live |

    ```swift
    let answer = 42
    ```
    """
}

extension UTType {
    static let textworkMarkdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

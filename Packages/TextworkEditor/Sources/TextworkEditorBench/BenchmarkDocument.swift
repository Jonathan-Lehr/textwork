import Foundation

func makeDocument(utf8ByteCount: Int) -> String {
    let section = """
    # Heading

    A paragraph with *emphasis*, **strong**, and `code` plus a [link](https://example.com) and an image ![Alt](images/figure.png).

    > A quoted line with *nested* emphasis.

    - item one
    - item two with `code`

    | Syntax | Shown |
    | --- | --- |
    | raw | live |

    ```swift
    let answer = 42
    ```

    """
    var text = ""
    while text.utf8.count < utf8ByteCount {
        text += section
    }
    if text.utf8.count == utf8ByteCount { return text }
    let utf8 = text.utf8
    let limit = utf8.index(utf8.startIndex, offsetBy: utf8ByteCount)
    guard let stringLimit = String.Index(limit, within: text) else { return text }
    if let newline = text[..<stringLimit].lastIndex(of: "\n") {
        return String(text[...newline])
    }
    return String(text[..<stringLimit])
}

func textByApplyingMiddleInsert(_ text: String) -> String {
    let midpoint = text.utf16.count / 2
    let index = String.Index(utf16Offset: midpoint, in: text)
    var updated = text
    updated.insert(contentsOf: "Z", at: index)
    return updated
}

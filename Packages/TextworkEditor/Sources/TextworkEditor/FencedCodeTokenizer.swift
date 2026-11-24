import Foundation

/// A language the fenced-code tokenizer knows.
enum FencedCodeLanguage: Equatable, Sendable {
    case swift
    case json
    case shell
    case html
}

/// Carry block comments, multiline strings, and a pending function name from one fence line to the next.
struct FencedCodeScanState: Equatable, Sendable {
    var blockCommentDepth: Int = 0
    var insideMultilineString: Bool = false
    var insideHTMLComment: Bool = false
    /// The next identifier is the name declared after `func`, so it stays plain.
    var awaitingFunctionName: Bool = false
    /// The next identifier is a `let` or `var` property in a type body.
    var awaitingPropertyName: Bool = false
    /// The next `{` opens a class, struct, enum, actor, extension, or protocol body.
    var nextBraceOpensTypeBody: Bool = false
    /// The next `{` opens a function, initializer, closure, or accessor body.
    var nextBraceOpensFunctionBody: Bool = false
    /// Outermost first. A type body is where `let` and `var` names are properties.
    var braceKinds: [SwiftBraceKind] = []
}

/// Whether a `{` block is a type declaration or a nested body of code.
enum SwiftBraceKind: Equatable, Sendable {
    case typeBody
    case functionBody
}

/// One colored token inside a fenced code line. Offsets are document bytes.
struct FencedCodeToken: Equatable, Sendable {
    var byteRange: Range<Int>
    var role: HighlightRole
}

/// Hand-written tokenizers for the languages the editor colors inside fences.
///
/// Swift, JSON, shell (`sh`, `bash`, `zsh`, and `shell`), and HTML are
/// recognized from the fence info word. Any other language returns no tokens,
/// so the line keeps the single code color. A fence is tokenized only when
/// that block is styled, which is the block the highlighter reparses after an
/// edit inside it.
enum FencedCodeTokenizer {
    static func language(named word: String) -> FencedCodeLanguage? {
        switch word.lowercased() {
        case "swift": .swift
        case "json": .json
        case "sh", "bash", "zsh", "shell": .shell
        case "html", "htm": .html
        default: nil
        }
    }

    /// Language of a fence opening line, or nil when the info word is unknown.
    static func language(onOpeningFence bytes: [UInt8], range: Range<Int>) -> FencedCodeLanguage? {
        guard let word = infoWord(bytes: bytes, range: range) else { return nil }
        return language(named: word)
    }

    static func tokens(
        bytes: [UInt8],
        range: Range<Int>,
        language: FencedCodeLanguage,
        state: inout FencedCodeScanState
    ) -> [FencedCodeToken] {
        guard range.upperBound > range.lowerBound else { return [] }
        var tokens: [FencedCodeToken] = []
        switch language {
        case .swift:
            scanSwift(bytes: bytes, range: range, state: &state, into: &tokens)
        case .json:
            scanJSON(bytes: bytes, range: range, into: &tokens)
        case .shell:
            scanShell(bytes: bytes, range: range, into: &tokens)
        case .html:
            scanHTML(bytes: bytes, range: range, state: &state, into: &tokens)
        }
        return tokens
    }

    /// HTML for a fenced code body. Unknown languages are escaped and not colored.
    static func html(for text: String, languageName: String?) -> String {
        guard let languageName, let language = language(named: languageName) else {
            return escapeRaw(text)
        }
        let bytes = Array(text.utf8)
        var state = FencedCodeScanState()
        var html = ""
        var lineStart = 0
        var index = 0
        while index <= bytes.count {
            let atEnd = index == bytes.count
            let newline = !atEnd && bytes[index] == 0x0A
            if atEnd || newline {
                let line = lineStart..<index
                if !line.isEmpty {
                    let lineTokens = tokens(bytes: bytes, range: line, language: language, state: &state)
                    html += htmlLine(bytes: bytes, range: line, tokens: lineTokens)
                }
                if newline {
                    html += "\n"
                    index += 1
                    lineStart = index
                    continue
                }
                break
            }
            index += 1
        }
        return html
    }

    static func cssClass(for role: HighlightRole) -> String? {
        switch role {
        case .codeKeyword: "code-keyword"
        case .codeString: "code-string"
        case .codeNumber: "code-number"
        case .codeComment: "code-comment"
        case .codeType: "code-type"
        case .codeTag: "code-tag"
        case .codeAttribute: "code-attribute"
        case .codeMember: "code-member"
        case .codeSystemType: "code-system-type"
        default: nil
        }
    }
}

private let swiftKeywords: Set<String> = [
    "associatedtype", "async", "await", "actor", "as", "break", "case", "catch", "class",
    "continue", "convenience", "default", "defer", "deinit", "didSet", "do", "else", "enum",
    "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "get", "guard",
    "if", "import", "in", "indirect", "init", "inout", "internal", "is", "lazy", "let",
    "mutating", "nil", "open", "operator", "override", "private", "protocol", "public",
    "repeat", "required", "return", "self", "Self", "set", "some", "static", "struct",
    "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "unowned",
    "var", "weak", "where", "while", "willSet",
]

private let shellKeywords: Set<String> = [
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
    "in", "function", "select", "time", "return", "exit", "local", "export", "readonly",
    "declare", "typeset", "unset", "source", "alias",
]

private let jsonKeywords: Set<String> = ["true", "false", "null"]

private func infoWord(bytes: [UInt8], range: Range<Int>) -> String? {
    var index = range.lowerBound
    var columns = 0
    while index < range.upperBound && columns < 4 {
        if bytes[index] == 0x20 {
            columns += 1
            index += 1
        } else if bytes[index] == 0x09 {
            columns += 4
            index += 1
        } else {
            break
        }
    }
    guard index < range.upperBound else { return nil }
    let marker = bytes[index]
    guard marker == 0x60 || marker == 0x7E else { return nil }
    while index < range.upperBound && bytes[index] == marker { index += 1 }
    while index < range.upperBound && (bytes[index] == 0x20 || bytes[index] == 0x09) { index += 1 }
    let start = index
    while index < range.upperBound {
        let byte = bytes[index]
        if byte == 0x20 || byte == 0x09 { break }
        index += 1
    }
    guard index > start else { return nil }
    return String(decoding: bytes[start..<index], as: UTF8.self)
}

private func scanSwift(
    bytes: [UInt8],
    range: Range<Int>,
    state: inout FencedCodeScanState,
    into tokens: inout [FencedCodeToken]
) {
    var index = range.lowerBound
    let limit = range.upperBound
    if state.insideMultilineString {
        if let close = tripleQuote(bytes, from: index, limit: limit) {
            appendToken(index..<close, role: .codeString, into: &tokens)
            state.insideMultilineString = false
            index = close
        } else {
            appendToken(index..<limit, role: .codeString, into: &tokens)
            return
        }
    }
    if state.blockCommentDepth > 0 {
        index = consumeSwiftBlockComment(bytes, from: index, limit: limit, state: &state, into: &tokens, openAt: index)
        if index >= limit { return }
    }
    while index < limit {
        let byte = bytes[index]
        if byte == 0x2F, index + 1 < limit, bytes[index + 1] == 0x2F {
            appendToken(index..<limit, role: .codeComment, into: &tokens)
            return
        }
        if byte == 0x2F, index + 1 < limit, bytes[index + 1] == 0x2A {
            let open = index
            index += 2
            state.blockCommentDepth = 1
            index = consumeSwiftBlockComment(bytes, from: index, limit: limit, state: &state, into: &tokens, openAt: open)
            continue
        }
        if byte == 0x22 {
            if index + 2 < limit, bytes[index + 1] == 0x22, bytes[index + 2] == 0x22 {
                let open = index
                index += 3
                if let close = tripleQuote(bytes, from: index, limit: limit) {
                    appendToken(open..<close, role: .codeString, into: &tokens)
                    index = close
                } else {
                    appendToken(open..<limit, role: .codeString, into: &tokens)
                    state.insideMultilineString = true
                    return
                }
                continue
            }
            index = consumeQuotedString(bytes, from: index, limit: limit, quote: 0x22, role: .codeString, into: &tokens)
            continue
        }
        if byte == 0x40, index + 1 < limit, isIdentifierStart(bytes[index + 1]) {
            let start = index
            index += 1
            index = consumeIdentifier(bytes, from: index, limit: limit)
            appendToken(start..<index, role: .codeAttribute, into: &tokens)
            continue
        }
        if byte == 0x7B {
            openSwiftBrace(&state)
            index += 1
            continue
        }
        if byte == 0x7D {
            closeSwiftBrace(&state)
            index += 1
            continue
        }
        if isDigit(byte) {
            index = consumeNumber(bytes, from: index, limit: limit, into: &tokens)
            state.awaitingPropertyName = false
            continue
        }
        if isIdentifierStart(byte) {
            let start = index
            index = consumeIdentifier(bytes, from: index, limit: limit)
            let word = String(decoding: bytes[start..<index], as: UTF8.self)
            if swiftKeywords.contains(word) {
                appendToken(start..<index, role: .codeKeyword, into: &tokens)
                noteSwiftKeyword(word, state: &state)
            } else if state.awaitingFunctionName {
                state.awaitingFunctionName = false
                state.awaitingPropertyName = false
            } else if state.awaitingPropertyName {
                state.awaitingPropertyName = false
                appendToken(start..<index, role: .codeMember, into: &tokens)
            } else if isSystemTypeName(word) {
                appendToken(start..<index, role: .codeSystemType, into: &tokens)
            } else if byte >= 0x41 && byte <= 0x5A {
                appendToken(start..<index, role: .codeType, into: &tokens)
            } else if identifierFollowsDot(bytes, start: start, lineStart: range.lowerBound)
                || identifierPrecedesParenthesis(bytes, end: index, limit: limit) {
                appendToken(start..<index, role: .codeMember, into: &tokens)
            }
            continue
        }
        if byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D {
            state.awaitingPropertyName = false
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
}

private func scanJSON(
    bytes: [UInt8],
    range: Range<Int>,
    into tokens: inout [FencedCodeToken]
) {
    var index = range.lowerBound
    let limit = range.upperBound
    while index < limit {
        let byte = bytes[index]
        if byte == 0x22 {
            index = consumeQuotedString(bytes, from: index, limit: limit, quote: 0x22, role: .codeString, into: &tokens)
            continue
        }
        if byte == 0x2D, index + 1 < limit, isDigit(bytes[index + 1]) {
            index = consumeNumber(bytes, from: index, limit: limit, into: &tokens)
            continue
        }
        if isDigit(byte) {
            index = consumeNumber(bytes, from: index, limit: limit, into: &tokens)
            continue
        }
        if isIdentifierStart(byte) {
            let start = index
            index = consumeIdentifier(bytes, from: index, limit: limit)
            let word = String(decoding: bytes[start..<index], as: UTF8.self)
            if jsonKeywords.contains(word) {
                appendToken(start..<index, role: .codeKeyword, into: &tokens)
            }
            continue
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
}

private func scanShell(
    bytes: [UInt8],
    range: Range<Int>,
    into tokens: inout [FencedCodeToken]
) {
    var index = range.lowerBound
    let limit = range.upperBound
    while index < limit {
        let byte = bytes[index]
        if byte == 0x23, !previousIsDollar(bytes, index) {
            appendToken(index..<limit, role: .codeComment, into: &tokens)
            return
        }
        if byte == 0x27 || byte == 0x22 {
            index = consumeQuotedString(bytes, from: index, limit: limit, quote: byte, role: .codeString, into: &tokens)
            continue
        }
        if isDigit(byte) {
            index = consumeNumber(bytes, from: index, limit: limit, into: &tokens)
            continue
        }
        if isIdentifierStart(byte) {
            let start = index
            index = consumeIdentifier(bytes, from: index, limit: limit)
            let word = String(decoding: bytes[start..<index], as: UTF8.self)
            if shellKeywords.contains(word) {
                appendToken(start..<index, role: .codeKeyword, into: &tokens)
            }
            continue
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
}

private func scanHTML(
    bytes: [UInt8],
    range: Range<Int>,
    state: inout FencedCodeScanState,
    into tokens: inout [FencedCodeToken]
) {
    var index = range.lowerBound
    let limit = range.upperBound
    if state.insideHTMLComment {
        if let close = seekASCII(bytes, from: index, limit: limit, ascii: "-->") {
            appendToken(index..<close, role: .codeComment, into: &tokens)
            state.insideHTMLComment = false
            index = close
        } else {
            appendToken(index..<limit, role: .codeComment, into: &tokens)
            return
        }
    }
    while index < limit {
        if hasASCII(bytes, at: index, limit: limit, ascii: "<!--") {
            let open = index
            if let close = seekASCII(bytes, from: index + 4, limit: limit, ascii: "-->") {
                appendToken(open..<close, role: .codeComment, into: &tokens)
                index = close
            } else {
                appendToken(open..<limit, role: .codeComment, into: &tokens)
                state.insideHTMLComment = true
                return
            }
            continue
        }
        if bytes[index] == 0x3C, index + 1 < limit {
            let next = bytes[index + 1]
            if isIdentifierStart(next) || next == 0x2F {
                index = consumeHTMLTag(bytes, from: index, limit: limit, into: &tokens)
                continue
            }
        }
        index += DocumentBuffer.scalarWidth(bytes, index).0
    }
}

private func consumeHTMLTag(
    _ bytes: [UInt8],
    from start: Int,
    limit: Int,
    into tokens: inout [FencedCodeToken]
) -> Int {
    var index = start + 1
    if index < limit, bytes[index] == 0x2F { index += 1 }
    let nameStart = index
    while index < limit, isNameByte(bytes[index]) { index += 1 }
    if index > nameStart {
        appendToken(nameStart..<index, role: .codeTag, into: &tokens)
    }
    while index < limit, bytes[index] != 0x3E {
        let byte = bytes[index]
        if byte == 0x22 || byte == 0x27 {
            index = consumeQuotedString(bytes, from: index, limit: limit, quote: byte, role: .codeString, into: &tokens)
            continue
        }
        if isIdentifierStart(byte) {
            let attributeStart = index
            index = consumeIdentifier(bytes, from: index, limit: limit)
            while index < limit, isNameByte(bytes[index]) { index += 1 }
            appendToken(attributeStart..<index, role: .codeAttribute, into: &tokens)
            continue
        }
        index += 1
    }
    if index < limit { index += 1 }
    return index
}

private func consumeSwiftBlockComment(
    _ bytes: [UInt8],
    from start: Int,
    limit: Int,
    state: inout FencedCodeScanState,
    into tokens: inout [FencedCodeToken],
    openAt: Int
) -> Int {
    var index = start
    while index + 1 < limit, state.blockCommentDepth > 0 {
        if bytes[index] == 0x2F, bytes[index + 1] == 0x2A {
            state.blockCommentDepth += 1
            index += 2
            continue
        }
        if bytes[index] == 0x2A, bytes[index + 1] == 0x2F {
            state.blockCommentDepth -= 1
            index += 2
            continue
        }
        index += 1
    }
    if state.blockCommentDepth > 0 {
        appendToken(openAt..<limit, role: .codeComment, into: &tokens)
        return limit
    }
    appendToken(openAt..<index, role: .codeComment, into: &tokens)
    return index
}

private func consumeQuotedString(
    _ bytes: [UInt8],
    from start: Int,
    limit: Int,
    quote: UInt8,
    role: HighlightRole,
    into tokens: inout [FencedCodeToken]
) -> Int {
    var index = start + 1
    while index < limit {
        let byte = bytes[index]
        if byte == 0x5C, index + 1 < limit {
            index += 2
            continue
        }
        if byte == quote {
            index += 1
            break
        }
        if byte == 0x0A { break }
        index += 1
    }
    appendToken(start..<index, role: role, into: &tokens)
    return index
}

private func consumeNumber(
    _ bytes: [UInt8],
    from start: Int,
    limit: Int,
    into tokens: inout [FencedCodeToken]
) -> Int {
    var index = start
    if bytes[index] == 0x2D, index + 1 < limit { index += 1 }
    if index + 1 < limit, bytes[index] == 0x30, bytes[index + 1] == 0x78 || bytes[index + 1] == 0x58 {
        index += 2
        while index < limit, isHexDigit(bytes[index]) || bytes[index] == 0x5F { index += 1 }
    } else {
        while index < limit, isDigit(bytes[index]) || bytes[index] == 0x5F { index += 1 }
        if index < limit, bytes[index] == 0x2E, index + 1 < limit, isDigit(bytes[index + 1]) {
            index += 1
            while index < limit, isDigit(bytes[index]) || bytes[index] == 0x5F { index += 1 }
        }
        if index < limit, bytes[index] == 0x65 || bytes[index] == 0x45 {
            let exponent = index + 1
            var cursor = exponent
            if cursor < limit, bytes[cursor] == 0x2B || bytes[cursor] == 0x2D { cursor += 1 }
            if cursor < limit, isDigit(bytes[cursor]) {
                index = cursor
                while index < limit, isDigit(bytes[index]) { index += 1 }
            }
        }
    }
    appendToken(start..<index, role: .codeNumber, into: &tokens)
    return index
}

private func consumeIdentifier(_ bytes: [UInt8], from start: Int, limit: Int) -> Int {
    var index = start
    while index < limit, isIdentifierByte(bytes[index]) { index += 1 }
    return index
}

private func tripleQuote(_ bytes: [UInt8], from start: Int, limit: Int) -> Int? {
    var index = start
    while index + 2 < limit {
        if bytes[index] == 0x22, bytes[index + 1] == 0x22, bytes[index + 2] == 0x22 {
            return index + 3
        }
        index += 1
    }
    return nil
}

private func seekASCII(_ bytes: [UInt8], from start: Int, limit: Int, ascii: String) -> Int? {
    let needle = Array(ascii.utf8)
    guard !needle.isEmpty else { return nil }
    var index = start
    while index + needle.count <= limit {
        if Array(bytes[index..<(index + needle.count)]) == needle {
            return index + needle.count
        }
        index += 1
    }
    return nil
}

private func hasASCII(_ bytes: [UInt8], at index: Int, limit: Int, ascii: String) -> Bool {
    let prefix = Array(ascii.utf8)
    guard index + prefix.count <= limit else { return false }
    return Array(bytes[index..<(index + prefix.count)]) == prefix
}

private func appendToken(_ range: Range<Int>, role: HighlightRole, into tokens: inout [FencedCodeToken]) {
    guard range.upperBound > range.lowerBound else { return }
    tokens.append(FencedCodeToken(byteRange: range, role: role))
}

private func htmlLine(bytes: [UInt8], range: Range<Int>, tokens: [FencedCodeToken]) -> String {
    var html = ""
    var cursor = range.lowerBound
    for token in tokens where token.byteRange.lowerBound >= cursor && token.byteRange.upperBound <= range.upperBound {
        if token.byteRange.lowerBound > cursor {
            html += escapeRaw(String(decoding: bytes[cursor..<token.byteRange.lowerBound], as: UTF8.self))
        }
        let word = escapeRaw(String(decoding: bytes[token.byteRange], as: UTF8.self))
        if let cssClass = FencedCodeTokenizer.cssClass(for: token.role) {
            html += "<span class=\"\(cssClass)\">\(word)</span>"
        } else {
            html += word
        }
        cursor = token.byteRange.upperBound
    }
    if cursor < range.upperBound {
        html += escapeRaw(String(decoding: bytes[cursor..<range.upperBound], as: UTF8.self))
    }
    return html
}

private func previousIsDollar(_ bytes: [UInt8], _ index: Int) -> Bool {
    index > 0 && bytes[index - 1] == 0x24
}

private func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
private func isHexDigit(_ byte: UInt8) -> Bool {
    isDigit(byte) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66)
}
private func noteSwiftKeyword(_ word: String, state: inout FencedCodeScanState) {
    switch word {
    case "func", "init", "subscript", "deinit", "get", "set", "willSet", "didSet":
        state.awaitingFunctionName = word == "func"
        state.awaitingPropertyName = false
        state.nextBraceOpensFunctionBody = true
        state.nextBraceOpensTypeBody = false
    case "class", "struct", "enum", "actor", "extension", "protocol":
        state.awaitingFunctionName = false
        state.awaitingPropertyName = false
        state.nextBraceOpensTypeBody = true
        state.nextBraceOpensFunctionBody = false
    case "let", "var":
        state.awaitingFunctionName = false
        state.awaitingPropertyName = state.braceKinds.last == .typeBody
    default:
        state.awaitingFunctionName = false
        state.awaitingPropertyName = false
    }
}

private func openSwiftBrace(_ state: inout FencedCodeScanState) {
    if state.nextBraceOpensTypeBody {
        state.braceKinds.append(.typeBody)
    } else {
        state.braceKinds.append(.functionBody)
    }
    state.nextBraceOpensTypeBody = false
    state.nextBraceOpensFunctionBody = false
    state.awaitingFunctionName = false
    state.awaitingPropertyName = false
}

private func closeSwiftBrace(_ state: inout FencedCodeScanState) {
    if !state.braceKinds.isEmpty {
        state.braceKinds.removeLast()
    }
    state.awaitingPropertyName = false
}

private func isSystemTypeName(_ word: String) -> Bool {
    if swiftSystemTypeNames.contains(word) { return true }
    for prefix in appleFrameworkPrefixes where word.count > prefix.count && word.hasPrefix(prefix) {
        let nextIndex = word.index(word.startIndex, offsetBy: prefix.count)
        let next = word[nextIndex]
        if next.isUppercase { return true }
    }
    return false
}

/// Longest prefixes first so `SCN` matches before a shorter prefix.
private let appleFrameworkPrefixes: [String] = [
    "SCN", "MTL", "WK", "NS", "UI", "CG", "CA", "CF", "AV", "MK", "SK",
    "UN", "CL", "CK", "PH", "GK", "HK", "CM", "CI", "CT", "PK", "AR", "VN",
].sorted { $0.count > $1.count }

private let swiftSystemTypeNames: Set<String> = [
    "String", "Int", "UInt", "Int8", "Int16", "Int32", "Int64",
    "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float", "Bool",
    "Character", "Array", "Dictionary", "Set", "Optional", "Result",
    "Error", "Never", "Void", "Any", "AnyObject", "Data", "Date", "URL",
    "UUID", "Binding", "State", "View", "Text", "Color", "Image",
    "Published", "ObservableObject", "MainActor", "Task", "Codable",
    "Equatable", "Hashable", "Observable", "ObservedObject", "StateObject",
]

/// True when a dot, ignoring spaces and tabs, is the character before the identifier.
private func identifierFollowsDot(_ bytes: [UInt8], start: Int, lineStart: Int) -> Bool {
    var index = start
    while index > lineStart {
        index -= 1
        let byte = bytes[index]
        if byte == 0x20 || byte == 0x09 { continue }
        return byte == 0x2E
    }
    return false
}

/// True when a parenthesis, ignoring spaces and tabs, follows the identifier.
private func identifierPrecedesParenthesis(_ bytes: [UInt8], end: Int, limit: Int) -> Bool {
    var index = end
    while index < limit {
        let byte = bytes[index]
        if byte == 0x20 || byte == 0x09 {
            index += 1
            continue
        }
        return byte == 0x28
    }
    return false
}

private func isIdentifierStart(_ byte: UInt8) -> Bool {
    (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
}
private func isIdentifierByte(_ byte: UInt8) -> Bool { isIdentifierStart(byte) || isDigit(byte) }
private func isNameByte(_ byte: UInt8) -> Bool { isIdentifierByte(byte) || byte == 0x2D || byte == 0x3A }

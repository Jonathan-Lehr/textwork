/// CommonMark link labels match after whitespace is collapsed and case is folded.
func normalizeReferenceLabel(_ label: String) -> String {
    var collapsed = ""
    collapsed.reserveCapacity(label.count)
    var pendingSpace = false
    var hasContent = false
    for character in label {
        if isReferenceLabelWhitespace(character) {
            if hasContent {
                pendingSpace = true
            }
            continue
        }
        if pendingSpace {
            collapsed.append(" ")
            pendingSpace = false
        }
        hasContent = true
        collapsed.append(character)
    }
    return collapsed.lowercased()
}

func isReferenceLabelWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t" || character == "\n" || character == "\r"
        || character == "\u{000B}" || character == "\u{000C}"
}

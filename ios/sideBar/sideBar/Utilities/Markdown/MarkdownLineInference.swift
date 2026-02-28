@preconcurrency import Foundation

@available(iOS 26.0, macOS 26.0, *)
enum MarkdownLineInference {
    static let renderedBlockquoteMarker: Character = "│"
    static let renderedBulletPrefix = "• "
    static let renderedTaskCheckedPrefix = "☑ "
    static let renderedTaskUncheckedPrefix = "☐ "

    private static let taskRegex = try? NSRegularExpression(pattern: #"^\s*[-+*]\s+\[[ xX]\]\s"#)
    private static let orderedRegex = try? NSRegularExpression(pattern: #"^\s*\d+\.\s"#)
    private static let bulletRegex = try? NSRegularExpression(pattern: #"^\s*[-+*]\s"#)
    private static let headingRegex = try? NSRegularExpression(pattern: #"^#{1,6}\s"#)
    private static let blockquoteRegex = try? NSRegularExpression(pattern: #"^\s*(?:>|│)\s"#)
    private static let leadingBlockquoteRegex = try? NSRegularExpression(pattern: #"^(?:\s*[>│▎]\s*)+"#)

    static func inferBlockKind(from lineText: String) -> BlockKind? {
        if isThematicBreakLine(lineText) {
            return .horizontalRule
        }

        if let listKind = inferListBlockKind(from: lineText) {
            return listKind
        }

        if let heading = headingBlockKind(from: lineText) {
            return heading
        }

        let range = NSRange(location: 0, length: lineText.utf16.count)
        if blockquoteRegex?.firstMatch(in: lineText, range: range) != nil {
            return .blockquote
        }
        return nil
    }

    static func inferListBlockKind(from lineText: String) -> BlockKind? {
        var trimmed = lineText.trimmingCharacters(in: .whitespaces)
        if let leadingBlockquoteRegex {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            if let match = leadingBlockquoteRegex.firstMatch(in: trimmed, range: range),
               let matchRange = Range(match.range, in: trimmed) {
                trimmed.removeSubrange(matchRange)
                trimmed = trimmed.trimmingCharacters(in: .whitespaces)
            }
        }

        if trimmed.hasPrefix(renderedTaskCheckedPrefix) {
            return .taskChecked
        }
        if trimmed.hasPrefix(renderedTaskUncheckedPrefix) {
            return .taskUnchecked
        }
        if trimmed.hasPrefix(renderedBulletPrefix) {
            return .bulletList
        }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return .taskChecked
        }
        if trimmed.hasPrefix("- [ ] ") {
            return .taskUnchecked
        }

        let range = NSRange(location: 0, length: trimmed.utf16.count)
        if taskRegex?.firstMatch(in: trimmed, range: range) != nil {
            let prefix = (trimmed as NSString)
                .substring(with: taskRegex?.firstMatch(in: trimmed, range: range)?.range ?? NSRange(location: 0, length: 0))
                .lowercased()
            return prefix.contains("[x]") ? .taskChecked : .taskUnchecked
        }
        if orderedRegex?.firstMatch(in: trimmed, range: range) != nil {
            return .orderedList
        }
        if bulletRegex?.firstMatch(in: trimmed, range: range) != nil {
            return .bulletList
        }
        return nil
    }

    static func isThematicBreakLine(_ lineText: String) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var marker: Character?
        var count = 0
        for character in trimmed {
            if character.isWhitespace {
                continue
            }
            guard character == "-" || character == "*" || character == "_" else { return false }
            if marker == nil {
                marker = character
            }
            guard character == marker else { return false }
            count += 1
        }
        return count >= 3
    }

    private static func headingBlockKind(from lineText: String) -> BlockKind? {
        let range = NSRange(location: 0, length: lineText.utf16.count)
        guard let regex = headingRegex,
              let match = regex.firstMatch(in: lineText, range: range) else {
            return nil
        }
        let prefix = (lineText as NSString).substring(with: match.range)
        let level = prefix.prefix { $0 == "#" }.count
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        case 6: return .heading6
        default: return nil
        }
    }
}

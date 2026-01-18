import Foundation

public enum ScratchpadConstants {
    public static let title = "✏️ Scratchpad"
    public static let heading = "# \(title)"
    public static let placeholder = "_Start typing to capture thoughts._"
}

public enum ScratchpadFormatting {
    public static func stripHeading(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(ScratchpadConstants.heading) else {
            return markdown
        }
        var remainder = trimmed.dropFirst(ScratchpadConstants.heading.count)
        while let first = remainder.first, first == "\n" || first == "\r" {
            remainder = remainder.dropFirst()
        }
        return String(remainder)
    }

    public static func withHeading(_ markdown: String) -> String {
        let body = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return ScratchpadConstants.heading + "\n"
        }
        return ScratchpadConstants.heading + "\n\n" + body + "\n"
    }

    public static func removeEmptyTaskItems(_ markdown: String) -> String {
        let pattern = #"(?m)^\s*[-*]\s+\[ \]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return markdown
        }
        let range = NSRange(markdown.startIndex..., in: markdown)
        let cleaned = regex.stringByReplacingMatches(in: markdown, range: range, withTemplate: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

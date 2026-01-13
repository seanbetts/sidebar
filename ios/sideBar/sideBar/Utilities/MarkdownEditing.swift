import Foundation

public struct MarkdownEditResult {
    public let text: String
    public let selectedRange: NSRange
}

public enum MarkdownEditing {
    public static func applyInlineStyle(
        text: String,
        range: NSRange,
        prefix: String,
        suffix: String,
        placeholder: String
    ) -> MarkdownEditResult {
        let safeRange = clamp(range: range, in: text)
        let replacement: String
        let selectionLength: Int

        if safeRange.length == 0 {
            replacement = "\(prefix)\(placeholder)\(suffix)"
            selectionLength = placeholder.utf16.count
        } else {
            let selected = (text as NSString).substring(with: safeRange)
            replacement = "\(prefix)\(selected)\(suffix)"
            selectionLength = safeRange.length
        }

        let updated = (text as NSString).replacingCharacters(in: safeRange, with: replacement)
        let selectionLocation = safeRange.location + prefix.utf16.count
        return MarkdownEditResult(
            text: updated,
            selectedRange: NSRange(location: selectionLocation, length: selectionLength)
        )
    }

    public static func toggleLinePrefix(
        text: String,
        range: NSRange,
        prefix: String
    ) -> MarkdownEditResult {
        return toggleLinePrefix(text: text, range: range) { _ in prefix }
    }

    public static func toggleOrderedList(
        text: String,
        range: NSRange
    ) -> MarkdownEditResult {
        return toggleLinePrefix(text: text, range: range) { index in "\(index + 1). " }
    }

    public static func toggleTaskList(
        text: String,
        range: NSRange
    ) -> MarkdownEditResult {
        return toggleLinePrefix(text: text, range: range) { _ in "- [ ] " }
    }

    public static func insertCodeBlock(
        text: String,
        range: NSRange,
        language: String = ""
    ) -> MarkdownEditResult {
        let safeRange = clamp(range: range, in: text)
        let selected = (text as NSString).substring(with: safeRange)
        let lang = language.isEmpty ? "" : language
        let block = "```\(lang)\n\(selected)\n```"
        let updated = (text as NSString).replacingCharacters(in: safeRange, with: block)
        let selectionStart = safeRange.location + 4 + lang.utf16.count
        let selectionLength = selected.isEmpty ? 0 : selected.utf16.count
        return MarkdownEditResult(
            text: updated,
            selectedRange: NSRange(location: selectionStart, length: selectionLength)
        )
    }

    public static func insertLink(
        text: String,
        range: NSRange,
        urlPlaceholder: String = "https://"
    ) -> MarkdownEditResult {
        let safeRange = clamp(range: range, in: text)
        let selected = (text as NSString).substring(with: safeRange)
        let linkText = selected.isEmpty ? "Link text" : selected
        let replacement = "[\(linkText)](\(urlPlaceholder))"
        let updated = (text as NSString).replacingCharacters(in: safeRange, with: replacement)
        let selectionLocation = safeRange.location + 1 + linkText.utf16.count + 2
        return MarkdownEditResult(
            text: updated,
            selectedRange: NSRange(location: selectionLocation, length: urlPlaceholder.utf16.count)
        )
    }

    public static func insertTable(
        text: String,
        range: NSRange,
        columns: Int = 2,
        rows: Int = 2
    ) -> MarkdownEditResult {
        let safeRange = clamp(range: range, in: text)
        let columnCount = max(columns, 2)
        let rowCount = max(rows, 1)
        let header = Array(repeating: "Header", count: columnCount)
        let separator = Array(repeating: "---", count: columnCount)
        let row = Array(repeating: "Cell", count: columnCount)

        let headerLine = "| " + header.joined(separator: " | ") + " |"
        let separatorLine = "| " + separator.joined(separator: " | ") + " |"
        let rowLine = "| " + row.joined(separator: " | ") + " |"
        let rowsBlock = Array(repeating: rowLine, count: rowCount).joined(separator: "\n")

        let table = "\(headerLine)\n\(separatorLine)\n\(rowsBlock)"
        let updated = (text as NSString).replacingCharacters(in: safeRange, with: table)
        let selectionLocation = safeRange.location + 2
        return MarkdownEditResult(
            text: updated,
            selectedRange: NSRange(location: selectionLocation, length: "Header".utf16.count)
        )
    }

    private static func toggleLinePrefix(
        text: String,
        range: NSRange,
        prefixProvider: (Int) -> String
    ) -> MarkdownEditResult {
        let nsText = text as NSString
        let safeRange = clamp(range: range, in: text)
        let lineRange = nsText.lineRange(for: safeRange)
        let lineText = nsText.substring(with: lineRange)
        let lines = lineText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let shouldRemove = lines.enumerated().allSatisfy { index, line in
            let prefix = prefixProvider(index)
            return line.hasPrefix(prefix)
        }

        let newLines = lines.enumerated().map { index, line -> String in
            let prefix = prefixProvider(index)
            if shouldRemove, line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
            if shouldRemove {
                return line
            }
            return "\(prefix)\(line)"
        }

        let updatedBlock = newLines.joined(separator: "\n")
        let updated = nsText.replacingCharacters(in: lineRange, with: updatedBlock)
        let delta = updatedBlock.utf16.count - lineText.utf16.count
        let newSelection = NSRange(
            location: lineRange.location,
            length: max(0, lineRange.length + delta)
        )
        return MarkdownEditResult(text: updated, selectedRange: newSelection)
    }

    private static func clamp(range: NSRange, in text: String) -> NSRange {
        let maxLength = text.utf16.count
        let location = max(0, min(range.location, maxLength))
        let length = max(0, min(range.length, maxLength - location))
        return NSRange(location: location, length: length)
    }
}

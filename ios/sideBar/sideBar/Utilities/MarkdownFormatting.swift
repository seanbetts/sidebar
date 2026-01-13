import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum MarkdownFormatting {
    private static let blockAttribute = NSAttributedString.Key("sideBarMarkdownBlock")
    private struct ParsedLine {
        let content: String
        let blockKind: String
        let paragraphStyle: NSParagraphStyle?
        let prefix: String?
        let listLevel: Int
    }

    public static func render(markdown: String) -> NSAttributedString {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        let result = NSMutableAttributedString()
        var isInCodeBlock = false
        var orderedCounters: [Int] = []
        var lastOrderedLevel: Int? = nil

        var index = 0
        while index < lines.count {
            let lineString = String(lines[index])
            if lineString.hasPrefix("```") {
                isInCodeBlock.toggle()
                index += 1
                continue
            }

            let nextLine = index + 1 < lines.count ? String(lines[index + 1]) : nil
            if !isInCodeBlock, shouldTreatAsTableHeader(lineString, nextLine: nextLine) {
                let tableResult = renderTable(from: lines, startIndex: index)
                result.append(tableResult.attributed)
                index = tableResult.nextIndex
                if index < lines.count {
                    result.append(NSAttributedString(string: "\n"))
                }
                continue
            }

            let parsed = parseLine(
                lineString,
                isInCodeBlock: isInCodeBlock
            )

            let contentAttributed = inlineAttributed(from: parsed.content, isCodeBlock: parsed.blockKind == "code")
            if let paragraphStyle = parsed.paragraphStyle {
                contentAttributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: contentAttributed.fullRange)
            }
            applyBaseFont(contentAttributed, blockKind: parsed.blockKind)
            if parsed.blockKind == "blockquote" {
                contentAttributed.addAttribute(.foregroundColor, value: secondaryTextColor(), range: contentAttributed.fullRange)
            }
            if parsed.blockKind == "code" {
                contentAttributed.addAttribute(.backgroundColor, value: codeBlockBackground(), range: contentAttributed.fullRange)
            }
            applyInlineStyles(contentAttributed, blockKind: parsed.blockKind)
            applyTaskStyleIfNeeded(contentAttributed, blockKind: parsed.blockKind)

            let lineAttributed = NSMutableAttributedString()
            if let prefix = listPrefix(for: parsed, orderedCounters: &orderedCounters, lastOrderedLevel: &lastOrderedLevel) {
                let prefixAttributed = NSMutableAttributedString(string: prefix)
                if let paragraphStyle = parsed.paragraphStyle {
                    prefixAttributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: prefixAttributed.fullRange)
                }
                applyBaseFont(prefixAttributed, blockKind: parsed.blockKind)
                lineAttributed.append(prefixAttributed)
            } else {
                lastOrderedLevel = nil
                orderedCounters = []
            }

            lineAttributed.append(contentAttributed)
            lineAttributed.addAttribute(blockAttribute, value: parsed.blockKind, range: lineAttributed.fullRange)
            result.append(lineAttributed)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
            index += 1
        }

        return result
    }

    public static func serialize(attributedText: NSAttributedString) -> String {
        let nsText = attributedText.string as NSString
        var output: [String] = []
        var index = 0
        var isInCodeBlock = false

        while index < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
            let lineInfo = trimmedLine(from: nsText, range: lineRange)
            let blockKind = attributedText.attribute(blockAttribute, at: lineRange.location, effectiveRange: nil) as? String
            var inlineSource = attributedText.attributedSubstring(from: lineInfo.contentRange)
            if let blockKind, blockKind.hasPrefix("task:") {
                inlineSource = stripTaskMarker(from: inlineSource)
            }
            if blockKind == "list:bullet" || blockKind == "list:ordered" || blockKind == "blockquote" {
                inlineSource = stripLeadingPrefix(from: inlineSource)
            }
            let inlineMarkdown = serializeInline(inlineSource)

            if blockKind == "code" {
                if !isInCodeBlock {
                    output.append("```")
                    isInCodeBlock = true
                }
                output.append(lineInfo.content)
            } else {
                if isInCodeBlock {
                    output.append("```")
                    isInCodeBlock = false
                }
                output.append(prefix(for: blockKind) + inlineMarkdown)
            }

            index = lineRange.location + lineRange.length
        }

        if isInCodeBlock {
            output.append("```")
        }

        return output.joined(separator: "\n")
    }

    private static func parseLine(
        _ line: String,
        isInCodeBlock: Bool
    ) -> ParsedLine {
        if isInCodeBlock {
            return ParsedLine(
                content: line,
                blockKind: "code",
                paragraphStyle: codeBlockStyle(),
                prefix: nil,
                listLevel: 0
            )
        }

        if line.hasPrefix("# ") {
            return ParsedLine(
                content: String(line.dropFirst(2)),
                blockKind: "heading1",
                paragraphStyle: headingStyle(level: 1),
                prefix: nil,
                listLevel: 0
            )
        }
        if line.hasPrefix("## ") {
            return ParsedLine(
                content: String(line.dropFirst(3)),
                blockKind: "heading2",
                paragraphStyle: headingStyle(level: 2),
                prefix: nil,
                listLevel: 0
            )
        }
        if line.hasPrefix("### ") {
            return ParsedLine(
                content: String(line.dropFirst(4)),
                blockKind: "heading3",
                paragraphStyle: headingStyle(level: 3),
                prefix: nil,
                listLevel: 0
            )
        }
        if let blockquoteMatch = matchBlockquote(line) {
            return ParsedLine(
                content: blockquoteMatch.content,
                blockKind: "blockquote",
                paragraphStyle: blockquoteStyle(),
                prefix: "│ ",
                listLevel: blockquoteMatch.level
            )
        }
        if let taskMatch = matchTaskItem(line) {
            return ParsedLine(
                content: taskMatch.content,
                blockKind: taskMatch.isChecked ? "task:checked" : "task:unchecked",
                paragraphStyle: listStyle(level: taskMatch.level),
                prefix: taskMatch.isChecked ? "☑ " : "☐ ",
                listLevel: taskMatch.level
            )
        }
        if let bulletMatch = matchBulletItem(line) {
            return ParsedLine(
                content: bulletMatch.content,
                blockKind: "list:bullet",
                paragraphStyle: listStyle(level: bulletMatch.level),
                prefix: "• ",
                listLevel: bulletMatch.level
            )
        }
        if let orderedMatch = matchOrderedItem(line) {
            return ParsedLine(
                content: orderedMatch.content,
                blockKind: "list:ordered",
                paragraphStyle: listStyle(level: orderedMatch.level),
                prefix: nil,
                listLevel: orderedMatch.level
            )
        }
        return ParsedLine(
            content: line,
            blockKind: "paragraph",
            paragraphStyle: paragraphStyle(),
            prefix: nil,
            listLevel: 0
        )
    }

    private static func matchBlockquote(_ line: String) -> (content: String, level: Int)? {
        let pattern = #"^(\s*)>\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, range: range),
              let indentRange = Range(match.range(at: 1), in: line),
              let contentRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        let level = indentLevel(from: String(line[indentRange]))
        return (String(line[contentRange]), level)
    }

    private static func matchTaskItem(_ line: String) -> (content: String, level: Int, isChecked: Bool)? {
        let pattern = #"^(\s*)[-+*]\s+\[([ xX])\]\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, range: range),
              let indentRange = Range(match.range(at: 1), in: line),
              let stateRange = Range(match.range(at: 2), in: line),
              let contentRange = Range(match.range(at: 3), in: line) else {
            return nil
        }
        let level = indentLevel(from: String(line[indentRange]))
        let state = line[stateRange]
        let isChecked = state == "x" || state == "X"
        return (String(line[contentRange]), level, isChecked)
    }

    private static func matchBulletItem(_ line: String) -> (content: String, level: Int)? {
        let pattern = #"^(\s*)[-+*]\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, range: range),
              let indentRange = Range(match.range(at: 1), in: line),
              let contentRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        let level = indentLevel(from: String(line[indentRange]))
        return (String(line[contentRange]), level)
    }

    private static func matchOrderedItem(_ line: String) -> (content: String, level: Int)? {
        let pattern = #"^(\s*)\d+\.\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, range: range),
              let indentRange = Range(match.range(at: 1), in: line),
              let contentRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        let level = indentLevel(from: String(line[indentRange]))
        return (String(line[contentRange]), level)
    }

    private static func indentLevel(from indent: String) -> Int {
        let expanded = indent.replacingOccurrences(of: "\t", with: "    ")
        return max(0, expanded.count / 2)
    }

    private static func inlineAttributed(from text: String, isCodeBlock: Bool) -> NSMutableAttributedString {
        if isCodeBlock {
            let attributed = NSMutableAttributedString(string: text)
            attributed.addAttribute(.font, value: codeFont(), range: attributed.fullRange)
            return attributed
        }

        let parts = text.split(separator: "`", omittingEmptySubsequences: false)
        let result = NSMutableAttributedString()
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )

        for (index, part) in parts.enumerated() {
            let segment = String(part)
            if index % 2 == 1 {
                let codeSegment = NSMutableAttributedString(string: segment)
                codeSegment.addAttribute(.font, value: inlineCodeFont(), range: codeSegment.fullRange)
                codeSegment.addAttribute(.backgroundColor, value: inlineCodeBackground(), range: codeSegment.fullRange)
                codeSegment.addAttribute(.foregroundColor, value: primaryTextColor(), range: codeSegment.fullRange)
                result.append(codeSegment)
            } else if let attributed = try? AttributedString(markdown: segment, options: options) {
                result.append(NSMutableAttributedString(attributed))
            } else {
                result.append(NSAttributedString(string: segment))
            }
        }

        return result
    }

    private static func stripTaskMarker(from attributed: NSAttributedString) -> NSAttributedString {
        let string = attributed.string
        if (string.hasPrefix("☐ ") || string.hasPrefix("☑ ")), attributed.length >= 2 {
            let range = NSRange(location: 2, length: attributed.length - 2)
            return attributed.attributedSubstring(from: range)
        }
        return attributed
    }

    private static func stripLeadingPrefix(from attributed: NSAttributedString) -> NSAttributedString {
        let string = attributed.string as NSString
        if string.hasPrefix("• ") || string.hasPrefix("│ ") {
            return attributed.attributedSubstring(from: NSRange(location: 2, length: max(0, attributed.length - 2)))
        }
        let pattern = #"^\d+\.\s+"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: string as String, range: NSRange(location: 0, length: string.length)) {
            let range = NSRange(location: match.range.length, length: max(0, attributed.length - match.range.length))
            return attributed.attributedSubstring(from: range)
        }
        return attributed
    }

    private static func trimmedLine(from text: NSString, range: NSRange) -> (content: String, contentRange: NSRange) {
        let lineText = text.substring(with: range)
        if lineText.hasSuffix("\r\n") {
            let trimmedRange = NSRange(location: range.location, length: max(0, range.length - 2))
            let trimmedText = text.substring(with: trimmedRange)
            return (trimmedText, trimmedRange)
        }
        if lineText.hasSuffix("\n") {
            let trimmedRange = NSRange(location: range.location, length: max(0, range.length - 1))
            let trimmedText = text.substring(with: trimmedRange)
            return (trimmedText, trimmedRange)
        }
        return (lineText, range)
    }

    private static func serializeInline(_ attributed: NSAttributedString) -> String {
        var output = ""
        attributed.enumerateAttributes(in: fullRange(for: attributed), options: []) { attributes, range, _ in
            let text = (attributed.string as NSString).substring(with: range)
            let font = attributes[.font] as? PlatformFont
            let isBold = font?.isBold ?? false
            let isItalic = font?.isItalic ?? false
            let isMonospace = font?.isMonospace ?? false
            let isStrike = (attributes[.strikethroughStyle] as? Int ?? 0) > 0
            let link = attributes[.link]

            var prefix = ""
            var suffix = ""

            if isMonospace {
                prefix += "`"
                suffix = "`" + suffix
            }
            if isStrike {
                prefix += "~~"
                suffix = "~~" + suffix
            }
            if isItalic {
                prefix += "*"
                suffix = "*" + suffix
            }
            if isBold {
                prefix += "**"
                suffix = "**" + suffix
            }

            if let link {
                output += "[\(text)](\(link))"
            } else {
                output += "\(prefix)\(text)\(suffix)"
            }
        }
        return output
    }

    private static func prefix(for blockKind: String?) -> String {
        switch blockKind {
        case "heading1":
            return "# "
        case "heading2":
            return "## "
        case "heading3":
            return "### "
        case "blockquote":
            return "> "
        case "list:bullet":
            return "- "
        case "list:ordered":
            return "1. "
        case "task:checked":
            return "- [x] "
        case "task:unchecked":
            return "- [ ] "
        default:
            return ""
        }
    }

    private static func listStyle(level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = em(1.5) * CGFloat(level + 1)
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.lineHeightMultiple = 1.4
        style.paragraphSpacing = 0
        return style
    }

    private static func headingStyle(level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let spacing = em(0.5)
        style.paragraphSpacingBefore = level == 1 ? 0 : spacing
        style.paragraphSpacing = spacing
        style.lineHeightMultiple = 1.2
        return style
    }

    private static func blockquoteStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = em(1.0)
        style.headIndent = indent
        style.firstLineHeadIndent = indent
        style.lineHeightMultiple = 1.6
        return style
    }

    private static func codeBlockStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = em(1.0)
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.lineHeightMultiple = 1.5
        return style
    }

    private static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.6
        return style
    }

    private static func tableStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.4
        return style
    }

    private static func shouldTreatAsTableHeader(_ line: String, nextLine: String?) -> Bool {
        guard line.contains("|"), let nextLine else { return false }
        return isTableSeparator(nextLine)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let pattern = #"^\s*\|?\s*[:\-]+\s*(\|\s*[:\-]+\s*)+\|?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }

    private static func renderTable(from lines: [Substring], startIndex: Int) -> (attributed: NSAttributedString, nextIndex: Int) {
        let headerLine = String(lines[startIndex])
        var index = startIndex + 1
        if index < lines.count, isTableSeparator(String(lines[index])) {
            index += 1
        }

        var rows: [[String]] = []
        while index < lines.count {
            let line = String(lines[index])
            if line.trimmingCharacters(in: .whitespaces).isEmpty || !line.contains("|") {
                break
            }
            rows.append(parseTableCells(line))
            index += 1
        }

        let headerCells = parseTableCells(headerLine)
        let columnCount = max(headerCells.count, rows.map(\.count).max() ?? 0)
        let paddedHeader = padCells(headerCells, to: columnCount)
        let paddedRows = rows.map { padCells($0, to: columnCount) }
        let widths = computeColumnWidths(cells: [paddedHeader] + paddedRows)

        let output = NSMutableAttributedString()
        let headerString = formatTableRow(cells: paddedHeader, widths: widths)
        let headerAttributed = NSMutableAttributedString(string: headerString)
        headerAttributed.addAttribute(.paragraphStyle, value: tableStyle(), range: headerAttributed.fullRange)
        headerAttributed.addAttribute(.backgroundColor, value: tableHeaderBackground(), range: headerAttributed.fullRange)
        headerAttributed.addAttribute(.font, value: tableFont(isHeader: true), range: headerAttributed.fullRange)
        headerAttributed.addAttribute(blockAttribute, value: "table:header", range: headerAttributed.fullRange)
        output.append(headerAttributed)

        for row in paddedRows {
            output.append(NSAttributedString(string: "\n"))
            let rowString = formatTableRow(cells: row, widths: widths)
            let rowAttributed = NSMutableAttributedString(string: rowString)
            rowAttributed.addAttribute(.paragraphStyle, value: tableStyle(), range: rowAttributed.fullRange)
            rowAttributed.addAttribute(.font, value: tableFont(isHeader: false), range: rowAttributed.fullRange)
            rowAttributed.addAttribute(blockAttribute, value: "table:row", range: rowAttributed.fullRange)
            output.append(rowAttributed)
        }

        return (output, index)
    }

    private static func parseTableCells(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return stripped.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func padCells(_ cells: [String], to count: Int) -> [String] {
        if cells.count >= count { return cells }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private static func computeColumnWidths(cells: [[String]]) -> [Int] {
        guard let first = cells.first else { return [] }
        var widths = Array(repeating: 0, count: first.count)
        for row in cells {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.count)
            }
        }
        return widths
    }

    private static func formatTableRow(cells: [String], widths: [Int]) -> String {
        let padded = cells.enumerated().map { index, cell in
            let pad = max(0, widths[index] - cell.count)
            return cell + String(repeating: " ", count: pad)
        }
        return "| " + padded.joined(separator: " | ") + " |"
    }

    private static func applyBaseFont(_ attributed: NSMutableAttributedString, blockKind: String) {
        let baseFont = bodyFont()
        let fontToApply: PlatformFont
        switch blockKind {
        case "heading1":
            fontToApply = sizedFont(multiplier: 2.0, weight: .bold)
        case "heading2":
            fontToApply = sizedFont(multiplier: 1.5, weight: .semibold)
        case "heading3":
            fontToApply = sizedFont(multiplier: 1.25, weight: .semibold)
        case "code":
            fontToApply = codeFont()
        case "table:header":
            fontToApply = sizedFont(multiplier: 0.95, weight: .semibold)
        case "table:row":
            fontToApply = sizedFont(multiplier: 0.95, weight: .regular)
        default:
            fontToApply = baseFont
        }

        if blockKind == "heading1"
            || blockKind == "heading2"
            || blockKind == "heading3"
            || blockKind == "code"
            || blockKind == "table:header"
            || blockKind == "table:row" {
            attributed.addAttribute(.font, value: fontToApply, range: attributed.fullRange)
            return
        }

        attributed.enumerateAttribute(.font, in: attributed.fullRange, options: []) { value, range, _ in
            if value == nil {
                attributed.addAttribute(.font, value: fontToApply, range: range)
            }
        }
    }

    private static func applyInlineStyles(_ attributed: NSMutableAttributedString, blockKind: String) {
        if blockKind == "code" {
            return
        }
        attributed.enumerateAttributes(in: attributed.fullRange, options: []) { attributes, range, _ in
            if attributes[.link] != nil {
                attributed.addAttribute(.foregroundColor, value: linkColor(), range: range)
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
    }

    private static func applyTaskStyleIfNeeded(_ attributed: NSMutableAttributedString, blockKind: String) {
        guard blockKind == "task:checked" else { return }
        let text = attributed.string as NSString
        let markerRange = text.range(of: "☑ ")
        let start = markerRange.location != NSNotFound ? markerRange.location + markerRange.length : 0
        let range = NSRange(location: start, length: max(0, attributed.length - start))
        attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        attributed.addAttribute(.foregroundColor, value: secondaryTextColor(), range: range)
    }

    private static func listPrefix(
        for parsed: ParsedLine,
        orderedCounters: inout [Int],
        lastOrderedLevel: inout Int?
    ) -> String? {
        if parsed.blockKind == "list:ordered" {
            let level = parsed.listLevel
            if orderedCounters.count <= level {
                orderedCounters += Array(repeating: 0, count: level - orderedCounters.count + 1)
            }
            if lastOrderedLevel == level {
                orderedCounters[level] += 1
            } else {
                orderedCounters[level] = 1
                if level < orderedCounters.count - 1 {
                    for index in (level + 1)..<orderedCounters.count {
                        orderedCounters[index] = 0
                    }
                }
            }
            lastOrderedLevel = level
            return "\(orderedCounters[level]). "
        }

        if parsed.blockKind.hasPrefix("list:")
            || parsed.blockKind.hasPrefix("task:")
            || parsed.blockKind == "blockquote" {
            lastOrderedLevel = nil
            orderedCounters = []
            return parsed.prefix ?? ""
        }

        return nil
    }
}

private extension NSMutableAttributedString {
    var fullRange: NSRange {
        NSRange(location: 0, length: length)
    }
}

private func fullRange(for attributed: NSAttributedString) -> NSRange {
    NSRange(location: 0, length: attributed.length)
}

#if os(macOS)
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
#else
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
#endif

private extension PlatformFont {
    var isBold: Bool {
        fontDescriptor.symbolicTraits.contains(.traitBold)
    }

    var isItalic: Bool {
        fontDescriptor.symbolicTraits.contains(.traitItalic)
    }

    var isMonospace: Bool {
        fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
    }
}

private func codeFont() -> PlatformFont {
    #if os(macOS)
    return NSFont.monospacedSystemFont(ofSize: bodyFont().pointSize * 0.875, weight: .regular)
    #else
    return UIFont.monospacedSystemFont(ofSize: bodyFont().pointSize * 0.875, weight: .regular)
    #endif
}

private func inlineCodeFont() -> PlatformFont {
    #if os(macOS)
    return NSFont.monospacedSystemFont(ofSize: bodyFont().pointSize * 0.875, weight: .regular)
    #else
    return UIFont.monospacedSystemFont(ofSize: bodyFont().pointSize * 0.875, weight: .regular)
    #endif
}

private func bodyFont() -> PlatformFont {
    #if os(macOS)
    return NSFont.preferredFont(forTextStyle: .body)
    #else
    return UIFont.preferredFont(forTextStyle: .body)
    #endif
}

private func sizedFont(multiplier: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
    #if os(macOS)
    return NSFont.systemFont(ofSize: bodyFont().pointSize * multiplier, weight: weight)
    #else
    return UIFont.systemFont(ofSize: bodyFont().pointSize * multiplier, weight: weight)
    #endif
}

private func em(_ multiplier: CGFloat) -> CGFloat {
    bodyFont().pointSize * multiplier
}

private func secondaryTextColor() -> PlatformColor {
    #if os(macOS)
    return PlatformColor(DesignTokens.Colors.textSecondary)
    #else
    return PlatformColor(DesignTokens.Colors.textSecondary)
    #endif
}

private func codeBlockBackground() -> PlatformColor {
    #if os(macOS)
    return PlatformColor(DesignTokens.Colors.muted)
    #else
    return PlatformColor(DesignTokens.Colors.muted)
    #endif
}

private func tableHeaderBackground() -> PlatformColor {
    PlatformColor(DesignTokens.Colors.muted)
}

private func tableFont(isHeader: Bool) -> PlatformFont {
    let weight: PlatformFont.Weight = isHeader ? .semibold : .regular
    #if os(macOS)
    return NSFont.monospacedSystemFont(ofSize: bodyFont().pointSize * 0.95, weight: weight)
    #else
    return UIFont.monospacedSystemFont(ofSize: bodyFont().pointSize * 0.95, weight: weight)
    #endif
}

private func inlineCodeBackground() -> PlatformColor {
    PlatformColor(DesignTokens.Colors.muted)
}

private func primaryTextColor() -> PlatformColor {
    PlatformColor(DesignTokens.Colors.textPrimary)
}

private func linkColor() -> PlatformColor {
    #if os(macOS)
    return PlatformColor(Color.accentColor)
    #else
    return PlatformColor(Color.accentColor)
    #endif
}

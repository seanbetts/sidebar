import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum MarkdownFormatting {
    private static let blockAttribute = NSAttributedString.Key("sideBarMarkdownBlock")

    public static func render(markdown: String) -> NSAttributedString {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        let result = NSMutableAttributedString()
        var isInCodeBlock = false

        for (index, line) in lines.enumerated() {
            let lineString = String(line)
            if lineString.hasPrefix("```") {
                isInCodeBlock.toggle()
                continue
            }

            let (content, blockKind, paragraphStyle) = parseLine(lineString, isInCodeBlock: isInCodeBlock)
            let lineAttributed = inlineAttributed(from: content, isCodeBlock: blockKind == "code")
            if let paragraphStyle {
                lineAttributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineAttributed.fullRange)
            }
            if let blockFont = font(for: blockKind) {
                lineAttributed.addAttribute(.font, value: blockFont, range: lineAttributed.fullRange)
            }
            if blockKind == "blockquote" {
                lineAttributed.addAttribute(.foregroundColor, value: secondaryTextColor(), range: lineAttributed.fullRange)
            }
            if blockKind == "code" {
                lineAttributed.addAttribute(.backgroundColor, value: codeBlockBackground(), range: lineAttributed.fullRange)
            }
            lineAttributed.addAttribute(blockAttribute, value: blockKind, range: lineAttributed.fullRange)
            result.append(lineAttributed)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
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

    private static func parseLine(_ line: String, isInCodeBlock: Bool) -> (String, String, NSParagraphStyle?) {
        if isInCodeBlock {
            return (line, "code", codeBlockStyle())
        }

        if line.hasPrefix("# ") {
            return (String(line.dropFirst(2)), "heading1", headingStyle(level: 1))
        }
        if line.hasPrefix("## ") {
            return (String(line.dropFirst(3)), "heading2", headingStyle(level: 2))
        }
        if line.hasPrefix("### ") {
            return (String(line.dropFirst(4)), "heading3", headingStyle(level: 3))
        }
        if line.hasPrefix("> ") {
            return (String(line.dropFirst(2)), "blockquote", blockquoteStyle())
        }
        if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
            return ("☑ " + String(line.dropFirst(6)), "task:checked", listStyle(ordered: false))
        }
        if line.hasPrefix("- [ ] ") {
            return ("☐ " + String(line.dropFirst(6)), "task:unchecked", listStyle(ordered: false))
        }
        if line.hasPrefix("- ") {
            return (String(line.dropFirst(2)), "list:bullet", listStyle(ordered: false))
        }
        if let orderedContent = orderedListPrefix(line) {
            return (orderedContent, "list:ordered", listStyle(ordered: true))
        }
        return (line, "paragraph", nil)
    }

    private static func orderedListPrefix(_ line: String) -> String? {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let numberPart = parts[0]
        guard numberPart.hasSuffix("."),
              Int(numberPart.dropLast()) != nil else { return nil }
        return String(parts[1])
    }

    private static func inlineAttributed(from text: String, isCodeBlock: Bool) -> NSMutableAttributedString {
        if isCodeBlock {
            let attributed = NSMutableAttributedString(string: text)
            attributed.addAttribute(.font, value: codeFont(), range: attributed.fullRange)
            return attributed
        }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return NSMutableAttributedString(attributed)
        }
        return NSMutableAttributedString(string: text)
    }

    private static func stripTaskMarker(from attributed: NSAttributedString) -> NSAttributedString {
        let string = attributed.string
        if (string.hasPrefix("☐ ") || string.hasPrefix("☑ ")), attributed.length >= 2 {
            let range = NSRange(location: 2, length: attributed.length - 2)
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

    private static func listStyle(ordered: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let marker = ordered ? NSTextList.MarkerFormat.decimal : NSTextList.MarkerFormat.disc
        let textList = NSTextList(markerFormat: marker, options: 0)
        style.textLists = [textList]
        style.firstLineHeadIndent = 16
        style.headIndent = 16
        return style
    }

    private static func headingStyle(level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = level == 1 ? 6 : 4
        style.paragraphSpacing = 4
        return style
    }

    private static func blockquoteStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = 12
        style.firstLineHeadIndent = 12
        return style
    }

    private static func codeBlockStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 6
        return style
    }

    private static func font(for blockKind: String) -> PlatformFont? {
        switch blockKind {
        case "heading1":
            return PlatformFont.preferredFont(forTextStyle: .title2)
        case "heading2":
            return PlatformFont.preferredFont(forTextStyle: .title3)
        case "heading3":
            return PlatformFont.preferredFont(forTextStyle: .headline)
        case "code":
            return codeFont()
        default:
            return nil
        }
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
    return NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    #else
    return UIFont.monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
    #endif
}

private func secondaryTextColor() -> PlatformColor {
    #if os(macOS)
    return NSColor.secondaryLabelColor
    #else
    return UIColor.secondaryLabel
    #endif
}

private func codeBlockBackground() -> PlatformColor {
    #if os(macOS)
    return NSColor.tertiaryLabelColor.withAlphaComponent(0.15)
    #else
    return UIColor.tertiarySystemFill
    #endif
}

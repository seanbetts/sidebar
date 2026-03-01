import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
struct NoteTextImporter {
    private let importer = MarkdownImporter()

    func attributedString(
        from content: String,
        baseFontSize: CGFloat = 16
    ) -> MarkdownImportResult {
        importer.attributedString(from: content, baseFontSize: baseFontSize)
    }
}

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextShortcutProcessor {
    struct ShortcutResult {
        let selection: AttributedTextSelection
    }

    static func processShortcuts(
        in text: inout AttributedString,
        selection: AttributedTextSelection,
        lastInsertedCharacter: Character?,
        baseFontSize: CGFloat = 16
    ) -> ShortcutResult? {
        guard let result = MarkdownShortcutProcessor.processShortcuts(
            in: &text,
            selection: selection,
            lastInsertedCharacter: lastInsertedCharacter,
            baseFontSize: baseFontSize
        ) else {
            return nil
        }
        return ShortcutResult(selection: result.selection)
    }

    static func inferredListBlockKind(from lineText: String) -> BlockKind? {
        MarkdownShortcutProcessor.inferredListBlockKind(from: lineText)
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct NoteTextFormattingDefinition {
    private let definition = MarkdownFormattingDefinition()

    func constrainedDocument(_ text: AttributedString) -> AttributedString {
        definition.constrainedDocument(text)
    }

    func constrainDocument(_ text: inout AttributedString) {
        definition.constrainDocument(&text)
    }
}

enum NoteTextTypography {
    static var defaultBodyFontSize: CGFloat {
        defaultBodyFontSize(for: AppTextSizeOption.resolved(
            from: UserDefaults.standard.string(forKey: AppStorageKeys.appTextSize)
                ?? AppTextSizeOption.system.rawValue
        ))
    }

    static func defaultBodyFontSize(for option: AppTextSizeOption) -> CGFloat {
        baseBodyFontSize * option.scaleMultiplier
    }

    static func inlineCodeFontSize(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * inlineCodeScale
    }

    static func footnoteFontSize(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * footnoteScale
    }

    private static var baseBodyFontSize: CGFloat {
#if canImport(UIKit)
        UIFont.preferredFont(forTextStyle: .body).pointSize
#elseif canImport(AppKit)
        NSFont.preferredFont(forTextStyle: .body).pointSize
#else
        16
#endif
    }

    private static let inlineCodeScale: CGFloat = 0.875
    private static let fallbackFootnoteScale: CGFloat = 13.0 / 16.0

    private static var footnoteScale: CGFloat {
#if canImport(UIKit)
        let bodySize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let footnoteSize = UIFont.preferredFont(forTextStyle: .footnote).pointSize
#elseif canImport(AppKit)
        let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
        let footnoteSize = NSFont.preferredFont(forTextStyle: .footnote).pointSize
#else
        let bodySize = CGFloat.zero
        let footnoteSize = CGFloat.zero
#endif
        guard bodySize > 0, footnoteSize > 0 else {
            return fallbackFootnoteScale
        }
        return footnoteSize / bodySize
    }
}

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextLineInference {
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
                .substring(
                    with: taskRegex?.firstMatch(in: trimmed, range: range)?.range
                        ?? NSRange(location: 0, length: 0)
                )
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

    private static func isThematicBreakLine(_ lineText: String) -> Bool {
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

enum NoteTextParagraphMetrics {
    private static let bodyLineHeightMultiple: CGFloat = 1.7
    static let bodySpacingRem: CGFloat = 0.5
    private static let listLineHeightMultiple: CGFloat = 1.4
    private static let rootListSpacingRem: CGFloat = 0.5
    private static let nestedListSpacingRem: CGFloat = 0
    private static let blockquoteSpacingRem: CGFloat = 1
    static let blockquoteIndentEm: CGFloat = 1

    static func bodyParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        paragraphStyle(
            fontSize: baseFontSize,
            lineHeightMultiple: bodyLineHeightMultiple,
            spacingBefore: bodySpacingRem * baseFontSize,
            spacingAfter: bodySpacingRem * baseFontSize,
            headIndent: headIndent,
            tailIndent: tailIndent
        )
    }

    static func listParagraphStyle(
        baseFontSize: CGFloat,
        listDepth: Int = 1,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let spacingRem = listDepth > 1 ? nestedListSpacingRem : rootListSpacingRem
        return paragraphStyle(
            fontSize: baseFontSize,
            lineHeightMultiple: listLineHeightMultiple,
            spacingBefore: spacingRem * baseFontSize,
            spacingAfter: spacingRem * baseFontSize,
            headIndent: headIndent,
            tailIndent: tailIndent
        )
    }

    static func blockquoteParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat
    ) -> NSParagraphStyle {
        return paragraphStyle(
            fontSize: baseFontSize,
            lineHeightMultiple: bodyLineHeightMultiple,
            spacingBefore: blockquoteSpacingRem * baseFontSize,
            spacingAfter: blockquoteSpacingRem * baseFontSize,
            headIndent: headIndent,
            tailIndent: 0
        )
    }

    private static func paragraphStyle(
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat,
        headIndent: CGFloat,
        tailIndent: CGFloat
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let desiredLineHeight = lineHeightMultiple * fontSize
        style.lineSpacing = max(0, desiredLineHeight - naturalLineHeight(for: fontSize))
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = headIndent
        style.firstLineHeadIndent = headIndent
        if tailIndent != 0 {
            style.tailIndent = -tailIndent
        }
        return style
    }

    private static func naturalLineHeight(for fontSize: CGFloat) -> CGFloat {
#if canImport(UIKit)
        return UIFont.systemFont(ofSize: fontSize, weight: .regular).lineHeight
#elseif canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        return font.ascender - font.descender + font.leading
#else
        return fontSize
#endif
    }
}

enum NoteTextHeadingMetrics {
    private static let lineHeightMultiple: CGFloat = 1.3
    private static let headingSpacingBeforeRem: CGFloat = 1
    private static let headingSpacingAfterRem: CGFloat = 0.3

    static func fontSize(
        for level: Int,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> CGFloat {
        headingScale(for: level) * baseFontSize
    }

    static func isBold(level: Int) -> Bool {
        level == 1
    }

    static func paragraphStyle(level: Int, baseFontSize: CGFloat) -> NSParagraphStyle {
        let fontSize = fontSize(for: level, baseFontSize: baseFontSize)
        let spacingBefore = (level == 1 ? 0 : headingSpacingBeforeRem) * baseFontSize
        let spacingAfter = headingSpacingAfterRem * baseFontSize
        let style = NSMutableParagraphStyle()
        let desiredLineHeight = lineHeightMultiple * fontSize
        style.lineSpacing = max(
            0,
            desiredLineHeight - naturalLineHeight(for: level, fontSize: fontSize)
        )
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        return style
    }

    private static func headingScale(for level: Int) -> CGFloat {
        switch level {
        case 1: return 2
        case 2: return 1.5
        case 3: return 1.25
        case 4: return 1.125
        case 5: return 1.0625
        default: return 1
        }
    }

    private static func naturalLineHeight(for level: Int, fontSize: CGFloat) -> CGFloat {
#if canImport(UIKit)
        let weight: UIFont.Weight = isBold(level: level) ? .bold : .semibold
        return UIFont.systemFont(ofSize: fontSize, weight: weight).lineHeight
#elseif canImport(AppKit)
        let weight: NSFont.Weight = isBold(level: level) ? .bold : .semibold
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return font.ascender - font.descender + font.leading
#else
        return fontSize
#endif
    }
}

struct NoteTextStyle: Equatable {
    let codeBackground: Color
    let codeBlockBackground: Color

    static let `default` = NoteTextStyle(markdownStyle: .default)

    private init(markdownStyle: SideBarMarkdownStyle) {
        self.codeBackground = markdownStyle.codeBackground
        self.codeBlockBackground = markdownStyle.codeBlockBackground
    }
}

@available(iOS 26.0, macOS 26.0, *)
typealias NoteTextEditorAttributes = AttributeScopes.MarkdownEditorAttributes

enum NoteTextLayout {
    static let maxContentWidth: CGFloat = SideBarMarkdownLayout.maxContentWidth
    static let horizontalPadding: CGFloat = SideBarMarkdownLayout.horizontalPadding
    static let verticalPadding: CGFloat = SideBarMarkdownLayout.verticalPadding
}

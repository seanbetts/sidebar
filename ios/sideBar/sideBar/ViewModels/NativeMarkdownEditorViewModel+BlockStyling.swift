@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModel {
    func applyInlineIntentStyling(
        in text: inout AttributedString,
        lineRange: Range<AttributedString.Index>,
        blockKind: BlockKind?
    ) {
        let baseFont = baseFont(for: blockKind)
        let baseBackground = baseBackgroundColor(for: blockKind)
        let baseForeground = baseForegroundColor(for: blockKind)
        let basePlatformFont = platformBaseFont(for: blockKind)
        for run in text[lineRange].runs {
            guard run.inlineMarker != true, run.listMarker != true else { continue }
            let intents = run.inlinePresentationIntent ?? []
            let range = run.range
            let tableInfo = tableRowInfo(from: run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self])

            if intents.contains(.code) {
                setFont(inlineCodeFont, platformFont: platformInlineCodeFont(), in: &text, range: range)
                setForegroundColor(DesignTokens.Colors.textPrimary, in: &text, range: range)
                setBackgroundColor(style.codeBackground, in: &text, range: range)
                continue
            }

            let isItalic = intents.contains(.emphasized)
            let isBold = intents.contains(.stronglyEmphasized)
                || tableInfo?.isHeader == true
                || (blockKind.map(isHeading) ?? false)
            var font = baseFont
            if isBold {
                font = font.weight(.bold)
            }
            if isItalic {
                font = font.italic()
            }
            let platformFont = platformFontApplyingTraits(
                basePlatformFont,
                bold: isBold,
                italic: isItalic
            )
            setFont(font, platformFont: platformFont, in: &text, range: range)
            let tableBackground = tableRowBackground(from: tableInfo)
            if let baseBackground {
                setBackgroundColor(baseBackground, in: &text, range: range)
            } else if let tableBackground {
                setBackgroundColor(tableBackground, in: &text, range: range)
            }
            if run.link != nil {
                setForegroundColor(.accentColor, in: &text, range: range)
            } else if run.imageInfo != nil {
                setForegroundColor(DesignTokens.Colors.textSecondary, in: &text, range: range)
            } else {
                setForegroundColor(baseForeground, in: &text, range: range)
            }
        }
    }

    func inferredBlockKind(from lineText: String) -> BlockKind? {
        if isThematicBreakLine(lineText) {
            return .horizontalRule
        }
        let range = NSRange(location: 0, length: lineText.utf16.count)

        if let regex = Self.taskRegex, let match = regex.firstMatch(in: lineText, range: range) {
            let prefix = (lineText as NSString).substring(with: match.range).lowercased()
            return prefix.contains("[x]") ? .taskChecked : .taskUnchecked
        }
        if Self.orderedRegex?.firstMatch(in: lineText, range: range) != nil {
            return .orderedList
        }
        if Self.bulletRegex?.firstMatch(in: lineText, range: range) != nil {
            return .bulletList
        }
        if let headingKind = headingBlockKind(in: lineText, range: range) {
            return headingKind
        }
        if Self.quoteRegex?.firstMatch(in: lineText, range: range) != nil {
            return .blockquote
        }
        return nil
    }

    func isThematicBreakLine(_ lineText: String) -> Bool {
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

    func headingBlockKind(in lineText: String, range: NSRange) -> BlockKind? {
        guard let regex = Self.headingRegex,
              let match = regex.firstMatch(in: lineText, range: range) else {
            return nil
        }
        let prefix = (lineText as NSString).substring(with: match.range)
        let count = prefix.prefix { $0 == "#" }.count
        switch count {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        case 6: return .heading6
        default: return nil
        }
    }

    func shouldShowPrefix(
        for lineRange: Range<Int>,
        selection: SelectionSnapshot
    ) -> Bool {
        guard !isReadOnly else { return false }
        switch selection {
        case .insertionPoint(let offset):
            return lineRange.contains(offset) || offset == lineRange.upperBound
        case .ranges(let ranges):
            return ranges.contains { range in
                if range.isEmpty {
                    return lineRange.contains(range.lowerBound) || range.lowerBound == lineRange.upperBound
                }
                return range.overlaps(lineRange)
            }
        }
    }

    func lineInfos(in text: AttributedString) -> [LineInfo] {
        var lines: [LineInfo] = []
        var startIndex = text.startIndex
        var currentIndex = text.startIndex
        var startOffset = 0
        var currentOffset = 0

        while currentIndex < text.endIndex {
            if text.characters[currentIndex].isNewline {
                let lineText = String(text[startIndex..<currentIndex].characters)
                lines.append(LineInfo(range: startOffset..<currentOffset, text: lineText))
                currentIndex = text.index(afterCharacter: currentIndex)
                currentOffset += 1
                startIndex = currentIndex
                startOffset = currentOffset
            } else {
                currentIndex = text.index(afterCharacter: currentIndex)
                currentOffset += 1
            }
        }

        let lineText = String(text[startIndex..<text.endIndex].characters)
        lines.append(LineInfo(range: startOffset..<currentOffset, text: lineText))
        return lines
    }

    func paragraphStyle(for blockKind: BlockKind, listDepth: Int? = nil) -> NSParagraphStyle? {
        if let headingLevel = headingLevel(for: blockKind) {
            return paragraphStyleForHeading(level: headingLevel)
        }

        switch blockKind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return paragraphStyleForHeading(level: headingLevel(for: blockKind) ?? 1)
        case .paragraph:
            return MarkdownParagraphMetrics.bodyParagraphStyle(baseFontSize: baseFontSize)
        case .blockquote:
            return MarkdownParagraphMetrics.blockquoteParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: em(MarkdownParagraphMetrics.blockquoteIndentEm, fontSize: baseFontSize)
            )
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            let depth = max(1, listDepth ?? 1)
            let listIndentUnit = em(1.5, fontSize: baseFontSize)
            let listIndent = listIndentUnit * CGFloat(depth)
            let style = MarkdownParagraphMetrics.listParagraphStyle(
                baseFontSize: baseFontSize,
                listDepth: depth,
                headIndent: listIndent
            )
            return style
        case .codeBlock:
            return paragraphStyle(
                lineSpacing: em(0.5, fontSize: inlineCodeFontSize),
                spacingBefore: 0,
                spacingAfter: 0,
                headIndent: DesignTokens.Spacing.md,
                tailIndent: DesignTokens.Spacing.md
            )
        case .horizontalRule:
            return paragraphStyle(
                lineSpacing: 0,
                spacingBefore: rem(0.75),
                spacingAfter: rem(0.75)
            )
        case .imageCaption:
            return paragraphStyle(
                lineSpacing: 0,
                spacingBefore: rem(0.25),
                spacingAfter: rem(0.75)
            )
        case .blankLine, .gallery, .htmlBlock:
            return paragraphStyle(
                lineSpacing: 0,
                spacingBefore: 0,
                spacingAfter: 0
            )
        @unknown default:
            return nil
        }
    }

    func paragraphStyleForHeading(level: Int) -> NSParagraphStyle {
        MarkdownHeadingMetrics.paragraphStyle(level: level, baseFontSize: baseFontSize)
    }

    func rem(_ value: CGFloat) -> CGFloat {
        value * baseFontSize
    }

    func em(_ value: CGFloat, fontSize: CGFloat) -> CGFloat {
        value * fontSize
    }

    func paragraphStyle(
        lineSpacing: CGFloat,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = headIndent
        style.firstLineHeadIndent = headIndent
        if tailIndent != 0 {
            style.tailIndent = -tailIndent
        }
        return style
    }

    func isListBlockKind(_ blockKind: BlockKind) -> Bool {
        switch blockKind {
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            return true
        default:
            return false
        }
    }

}

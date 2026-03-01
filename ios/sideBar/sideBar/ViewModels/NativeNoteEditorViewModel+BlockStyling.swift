@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
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
            let isTableHeader = tableInfo?.isHeader == true

            if intents.contains(.code) {
                setFont(inlineCodeFont, platformFont: platformInlineCodeFont(), in: &text, range: range)
                setForegroundColor(DesignTokens.Colors.textPrimary, in: &text, range: range)
                setBackgroundColor(Self.noteStyle.codeBackground, in: &text, range: range)
                continue
            }

            let isItalic = intents.contains(.emphasized)
            let isInlineBold = intents.contains(.stronglyEmphasized)
            var font = baseFont
            if isTableHeader {
                font = font.weight(.semibold)
            }
            if isInlineBold {
                font = font.weight(.bold)
            }
            if isItalic {
                font = font.italic()
            }
            let platformBase = isTableHeader
                ? platformSystemFont(size: baseFontSize, weight: .semibold)
                : basePlatformFont
            let platformFont = platformFontApplyingTraits(
                platformBase,
                bold: isInlineBold,
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
        NoteTextLineInference.inferBlockKind(from: lineText)
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
            return NoteTextParagraphMetrics.bodyParagraphStyle(baseFontSize: baseFontSize)
        case .blockquote:
            return NoteTextParagraphMetrics.blockquoteParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: em(NoteTextParagraphMetrics.blockquoteIndentEm, fontSize: baseFontSize)
            )
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            let depth = max(1, listDepth ?? 1)
            let listIndentUnit = em(1.5, fontSize: baseFontSize)
            let listIndent = listIndentUnit * CGFloat(depth)
            let style = NoteTextParagraphMetrics.listParagraphStyle(
                baseFontSize: baseFontSize,
                listDepth: depth,
                headIndent: listIndent
            )
            return style
        case .codeBlock:
            return paragraphStyle(
                lineSpacing: em(0.5, fontSize: inlineCodeFontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(1),
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
        NoteTextHeadingMetrics.paragraphStyle(level: level, baseFontSize: baseFontSize)
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

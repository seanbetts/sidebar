import Foundation
import SwiftUI

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
        MarkdownTypography.defaultBodyFontSize
    }

    static func defaultBodyFontSize(for option: AppTextSizeOption) -> CGFloat {
        MarkdownTypography.defaultBodyFontSize(for: option)
    }

    static func inlineCodeFontSize(baseFontSize: CGFloat) -> CGFloat {
        MarkdownTypography.inlineCodeFontSize(baseFontSize: baseFontSize)
    }

    static func footnoteFontSize(baseFontSize: CGFloat) -> CGFloat {
        MarkdownTypography.footnoteFontSize(baseFontSize: baseFontSize)
    }
}

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextLineInference {
    static func inferBlockKind(from lineText: String) -> BlockKind? {
        MarkdownLineInference.inferBlockKind(from: lineText)
    }
}

enum NoteTextParagraphMetrics {
    static let bodySpacingRem: CGFloat = MarkdownParagraphMetrics.bodySpacingRem
    static let blockquoteIndentEm: CGFloat = MarkdownParagraphMetrics.blockquoteIndentEm

    static func bodyParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        MarkdownParagraphMetrics.bodyParagraphStyle(
            baseFontSize: baseFontSize,
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
        MarkdownParagraphMetrics.listParagraphStyle(
            baseFontSize: baseFontSize,
            listDepth: listDepth,
            headIndent: headIndent,
            tailIndent: tailIndent
        )
    }

    static func blockquoteParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat
    ) -> NSParagraphStyle {
        MarkdownParagraphMetrics.blockquoteParagraphStyle(
            baseFontSize: baseFontSize,
            headIndent: headIndent
        )
    }
}

enum NoteTextHeadingMetrics {
    static func fontSize(for level: Int, baseFontSize: CGFloat) -> CGFloat {
        MarkdownHeadingMetrics.fontSize(for: level, baseFontSize: baseFontSize)
    }

    static func isBold(level: Int) -> Bool {
        MarkdownHeadingMetrics.isBold(level: level)
    }

    static func paragraphStyle(level: Int, baseFontSize: CGFloat) -> NSParagraphStyle {
        MarkdownHeadingMetrics.paragraphStyle(level: level, baseFontSize: baseFontSize)
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

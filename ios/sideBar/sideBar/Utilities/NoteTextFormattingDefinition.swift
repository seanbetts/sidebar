import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct NoteTextFormattingDefinition: AttributedTextFormattingDefinition {
    typealias Scope = AttributeScopes.NoteTextEditorAttributes
    let baseFontSize: CGFloat

    init(baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize) {
        self.baseFontSize = baseFontSize
    }

    var body: some AttributedTextFormattingDefinition<Scope> {
        NormalizeInlineFonts(baseFontSize: baseFontSize)
        PresentationIntentConstraint()
        ListItemDelimiterConstraint()
    }

    func constrainedDocument(_ text: AttributedString) -> AttributedString {
        var constrained = text
        constrainDocument(&constrained)
        return constrained
    }

    func constrainDocument(_ text: inout AttributedString) {
        let snapshots = text.runs.compactMap { run -> SupportedRunSnapshot? in
            guard !run.range.isEmpty else { return nil }
            let lower = text.characters.distance(from: text.startIndex, to: run.range.lowerBound)
            let upper = text.characters.distance(from: text.startIndex, to: run.range.upperBound)
            let resolvedBlockType = blockType(for: run, in: text)
            return SupportedRunSnapshot(
                range: lower..<upper,
                traits: inlineTraits(from: run, blockType: resolvedBlockType),
                underline: run.underlineStyle != nil,
                strikethrough: run.strikethroughStyle != nil,
                link: run.link,
                blockType: resolvedBlockType,
                noteBlock: run.noteBlock,
                structuralBoundary: run.noteStructuralBoundary == true
            )
        }

        for snapshot in snapshots {
            let range = attributedRange(for: snapshot.range, in: text)
            let replacement = normalizedRun(
                from: text[range],
                traits: snapshot.traits,
                underline: snapshot.underline,
                strikethrough: snapshot.strikethrough,
                link: snapshot.link,
                blockType: snapshot.blockType,
                noteBlock: snapshot.noteBlock,
                structuralBoundary: snapshot.structuralBoundary
            )
            text.replaceSubrange(range, with: replacement)
        }
    }

    private func normalizedRun(
        from slice: AttributedSubstring,
        traits: NoteInlineFormattingTraits,
        underline: Bool,
        strikethrough: Bool,
        link: URL?,
        blockType: NotesSemanticDocument.BlockType,
        noteBlock: String?,
        structuralBoundary: Bool
    ) -> AttributedString {
        var normalized = AttributedString(String(slice.characters))
        guard !normalized.characters.isEmpty else { return normalized }

        let range = normalized.startIndex..<normalized.endIndex
        normalized[range].font = blockFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: traits.bold,
            italic: traits.italic,
            inlineCode: traits.monospaced
        )
        #if os(iOS)
        normalized[range][AttributeScopes.UIKitAttributes.FontAttribute.self] = notePlatformFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: traits.bold,
            italic: traits.italic,
            inlineCode: traits.monospaced
        )
        #elseif os(macOS)
        normalized[range][AttributeScopes.AppKitAttributes.FontAttribute.self] = notePlatformFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: traits.bold,
            italic: traits.italic,
            inlineCode: traits.monospaced
        )
        #endif
        normalized[range].underlineStyle = underline ? .single : nil
        normalized[range].strikethroughStyle = strikethrough ? .single : nil
        normalized[range].link = link
        #if os(iOS)
        normalized[range][AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] =
            traits.monospaced ? NoteTextAppearance.inlineCodeBackgroundColor : nil
        #elseif os(macOS)
        normalized[range][AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] =
            traits.monospaced ? NoteTextAppearance.inlineCodeBackgroundColor : nil
        #endif
        normalized[range].paragraphStyle = paragraphStyle(for: blockType)
        normalized[range].noteBlock = noteBlock
        normalized[range].noteStructuralBoundary = structuralBoundary ? true : nil
        return normalized
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct NormalizeInlineFonts: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.NoteTextEditorAttributes
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.FontAttribute
    let baseFontSize: CGFloat

    func constrain(_ container: inout Attributes) {
        guard let font = container.font else { return }
        let traits = noteSwiftUIFontTraits(from: font)
        let blockType = NoteTextBlockAttribute.blockType(from: container.noteBlock) ?? .paragraph
        container.font = blockFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: traits.bold,
            italic: traits.italic,
            inlineCode: traits.monospaced
        )
    }

    private func blockFont(
        baseFontSize: CGFloat,
        blockType: NotesSemanticDocument.BlockType,
        bold: Bool,
        italic: Bool,
        inlineCode: Bool
    ) -> Font {
        let traits = noteResolvedInlineFormattingTraits(
            NoteInlineFormattingTraits(
                bold: bold,
                italic: italic,
                monospaced: inlineCode
            ),
            blockType: blockType
        )
        let design: Font.Design = traits.monospaced ? .monospaced : .default
        let baseSize = noteBlockPointSize(baseFontSize: baseFontSize, blockType: blockType)
        var resolvedFont: Font
        if let style = NoteTextStyle(blockType: blockType), !traits.monospaced {
            resolvedFont = NoteTextStyleTypography.font(for: style, baseFontSize: baseFontSize)
        } else {
            resolvedFont = Font.system(
                size: baseSize,
                weight: traits.bold ? .bold : .regular,
                design: design
            )
        }
        if traits.italic {
            resolvedFont = resolvedFont.italic()
        }
        return resolvedFont
    }

}

@available(iOS 26.0, macOS 26.0, *)
private struct PresentationIntentConstraint: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.NoteTextEditorAttributes
    typealias AttributeKey = AttributeScopes.FoundationAttributes.PresentationIntentAttribute

    func constrain(_ container: inout Attributes) {
        container[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ListItemDelimiterConstraint: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.NoteTextEditorAttributes
    typealias AttributeKey = AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute

    func constrain(_ container: inout Attributes) {
        container[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private extension NoteTextFormattingDefinition {
    struct SupportedRunSnapshot {
        let range: Range<Int>
        let traits: NoteInlineFormattingTraits
        let underline: Bool
        let strikethrough: Bool
        let link: URL?
        let blockType: NotesSemanticDocument.BlockType
        let noteBlock: String?
        let structuralBoundary: Bool
    }

    func inlineTraits(
        from run: AttributedString.Runs.Run,
        blockType: NotesSemanticDocument.BlockType
    ) -> NoteInlineFormattingTraits {
        noteSemanticInlineFormattingTraitsFromSwiftUIFont(
            from: run.attributes,
            blockType: blockType
        )
    }

    func attributedRange(
        for range: Range<Int>,
        in text: AttributedString
    ) -> Range<AttributedString.Index> {
        let lower = text.index(text.startIndex, offsetByCharacters: range.lowerBound)
        let upper = text.index(text.startIndex, offsetByCharacters: range.upperBound)
        return lower..<upper
    }

    func blockFont(
        baseFontSize: CGFloat,
        blockType: NotesSemanticDocument.BlockType,
        bold: Bool,
        italic: Bool,
        inlineCode: Bool
    ) -> Font {
        let traits = noteResolvedInlineFormattingTraits(
            NoteInlineFormattingTraits(
                bold: bold,
                italic: italic,
                monospaced: inlineCode
            ),
            blockType: blockType
        )
        let design: Font.Design = traits.monospaced ? .monospaced : .default
        let baseSize = noteBlockPointSize(baseFontSize: baseFontSize, blockType: blockType)
        var resolvedFont: Font
        if let style = NoteTextStyle(blockType: blockType), !traits.monospaced {
            resolvedFont = NoteTextStyleTypography.font(for: style, baseFontSize: baseFontSize)
        } else {
            resolvedFont = Font.system(
                size: baseSize,
                weight: traits.bold ? .bold : .regular,
                design: design
            )
        }
        if traits.italic {
            resolvedFont = resolvedFont.italic()
        }
        return resolvedFont
    }

    func blockType(
        for run: AttributedString.Runs.Run,
        in text: AttributedString
    ) -> NotesSemanticDocument.BlockType {
        NoteTextBlockResolution.resolvedBlockType(for: run, in: text)
    }

    func paragraphStyle(for blockType: NotesSemanticDocument.BlockType) -> NSParagraphStyle {
        switch blockType {
        case .unorderedList, .orderedList, .checklist:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize
            )
        case .blockquote:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 1.25
            )
        case .codeBlock:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 0.75,
                tailIndent: baseFontSize * 0.75
            )
        default:
            return NoteTextParagraphMetrics.paragraphStyle(for: blockType, baseFontSize: baseFontSize)
        }
    }
}

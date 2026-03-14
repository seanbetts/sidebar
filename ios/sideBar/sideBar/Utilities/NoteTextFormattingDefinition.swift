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
            return SupportedRunSnapshot(
                range: lower..<upper,
                traits: inlineTraits(from: run),
                underline: run.underlineStyle != nil,
                noteBlock: run.noteBlock
            )
        }

        for snapshot in snapshots {
            let range = attributedRange(for: snapshot.range, in: text)
            let replacement = normalizedRun(
                from: text[range],
                traits: snapshot.traits,
                underline: snapshot.underline,
                noteBlock: snapshot.noteBlock
            )
            text.replaceSubrange(range, with: replacement)
        }
    }

    private func normalizedRun(
        from slice: AttributedSubstring,
        traits: NoteInlineFormattingTraits,
        underline: Bool,
        noteBlock: String?
    ) -> AttributedString {
        var normalized = AttributedString(String(slice.characters))
        guard !normalized.characters.isEmpty else { return normalized }

        let range = normalized.startIndex..<normalized.endIndex
        let blockType = NoteTextBlockAttribute.blockType(from: noteBlock) ?? .paragraph
        normalized[range].font = blockFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: traits.bold,
            italic: traits.italic
        )
        normalized[range].underlineStyle = underline ? .single : nil
        normalized[range].paragraphStyle = paragraphStyle(for: blockType)
        normalized[range].noteBlock = noteBlock
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
            italic: traits.italic
        )
    }

    private func blockFont(
        baseFontSize: CGFloat,
        blockType: NotesSemanticDocument.BlockType,
        bold: Bool,
        italic: Bool
    ) -> Font {
        let size: CGFloat
        let design: Font.Design
        switch blockType {
        case .title:
            size = baseFontSize * 1.2
            design = .default
        case .heading:
            size = baseFontSize * 1.15
            design = .default
        case .subheading:
            size = baseFontSize * 1.08
            design = .default
        case .codeBlock:
            size = baseFontSize
            design = .monospaced
        default:
            size = baseFontSize
            design = .default
        }

        var font = Font.system(size: size, weight: bold ? .bold : .regular, design: design)
        if italic {
            font = font.italic()
        }
        return font
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
        let noteBlock: String?
    }

    func inlineTraits(from run: AttributedString.Runs.Run) -> NoteInlineFormattingTraits {
        noteInlineFormattingTraits(from: run.attributes)
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
        italic: Bool
    ) -> Font {
        let size: CGFloat
        let design: Font.Design
        switch blockType {
        case .title:
            size = baseFontSize * 1.2
            design = .default
        case .heading:
            size = baseFontSize * 1.15
            design = .default
        case .subheading:
            size = baseFontSize * 1.08
            design = .default
        case .codeBlock:
            size = baseFontSize
            design = .monospaced
        default:
            size = baseFontSize
            design = .default
        }

        var font = Font.system(size: size, weight: bold ? .bold : .regular, design: design)
        if italic {
            font = font.italic()
        }
        return font
    }

    func paragraphStyle(for blockType: NotesSemanticDocument.BlockType) -> NSParagraphStyle {
        switch blockType {
        case .unorderedList, .orderedList, .checklist:
            return NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: baseFontSize
            )
        case .blockquote:
            return NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 1.25
            )
        case .codeBlock:
            return NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 0.75,
                tailIndent: baseFontSize * 0.75
            )
        default:
            return NoteTextParagraphMetrics.bodyParagraphStyle(baseFontSize: baseFontSize)
        }
    }
}

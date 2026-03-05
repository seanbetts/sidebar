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
                underline: run.underlineStyle != nil
            )
        }

        for snapshot in snapshots {
            let range = attributedRange(for: snapshot.range, in: text)
            let replacement = normalizedRun(
                from: text[range],
                traits: snapshot.traits,
                underline: snapshot.underline
            )
            text.replaceSubrange(range, with: replacement)
        }
        if !text.characters.isEmpty {
            text[text.startIndex..<text.endIndex].paragraphStyle = NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize
            )
        }
    }

    private func normalizedRun(
        from slice: AttributedSubstring,
        traits: NoteInlineFormattingTraits,
        underline: Bool
    ) -> AttributedString {
        var normalized = AttributedString(String(slice.characters))
        guard !normalized.characters.isEmpty else { return normalized }

        let range = normalized.startIndex..<normalized.endIndex
        normalized[range].font = noteInlineFont(
            baseFontSize: baseFontSize,
            bold: traits.bold,
            italic: traits.italic
        )
        normalized[range].underlineStyle = underline ? .single : nil
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
        container.font = noteInlineFont(
            baseFontSize: baseFontSize,
            bold: traits.bold,
            italic: traits.italic
        )
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
}

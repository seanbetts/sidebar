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
        let snapshots = text.runs.compactMap { run -> (Range<Int>, NoteInlineFormattingTraits)? in
            guard !run.range.isEmpty else { return nil }
            let lower = text.characters.distance(from: text.startIndex, to: run.range.lowerBound)
            let upper = text.characters.distance(from: text.startIndex, to: run.range.upperBound)
            return (lower..<upper, inlineTraits(from: run))
        }

        for snapshot in snapshots {
            let range = attributedRange(for: snapshot.0, in: text)
            clearUnsupportedEditorAttributes(in: &text, range: range)
            text[range].font = noteInlineFont(
                baseFontSize: baseFontSize,
                bold: snapshot.1.bold,
                italic: snapshot.1.italic
            )
            noteApplyPlatformFont(
                notePlatformFont(
                    baseFontSize: baseFontSize,
                    bold: snapshot.1.bold,
                    italic: snapshot.1.italic
                ),
                to: &text,
                range: range
            )
        }
    }

    private func clearUnsupportedEditorAttributes(
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
        text[range].strikethroughStyle = nil
        if text[range].underlineStyle != nil {
            text[range].underlineStyle = .single
        }
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
    func inlineTraits(from run: AttributedString.Runs.Run) -> NoteInlineFormattingTraits {
        let swiftUIFontTraits = noteSwiftUIFontTraits(from: run.font)
        #if os(iOS)
        let platformFont = run[AttributeScopes.UIKitAttributes.FontAttribute.self]
        #else
        let platformFont: NotePlatformFont? = nil
        #endif
        let platformTraits = platformFont.map(notePlatformFontTraits(from:)) ??
            noteBridgedPlatformFont(from: run.attributes).map(notePlatformFontTraits(from:)) ??
            .plain
        return NoteInlineFormattingTraits(
            bold: swiftUIFontTraits.bold || platformTraits.bold,
            italic: swiftUIFontTraits.italic || platformTraits.italic
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
}

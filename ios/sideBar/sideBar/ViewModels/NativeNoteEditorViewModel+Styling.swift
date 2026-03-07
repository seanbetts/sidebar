@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func setFont(_ font: Font, in attrs: inout AttributeContainer) {
        attrs.font = font
    }

    func setFont(
        _ font: Font,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range].font = font
    }

    func inlineFormattingState(from attrs: AttributeContainer) -> InlineFormattingState {
        let swiftUIFontTraits = noteSwiftUIFontTraits(from: noteExplicitSwiftUIFont(from: attrs))
        return InlineFormattingState(
            bold: swiftUIFontTraits.bold,
            italic: swiftUIFontTraits.italic,
            underline: attrs.underlineStyle != nil
        )
    }

    func inlineFormattingState(from run: AttributedString.Runs.Run) -> InlineFormattingState {
        let swiftUIFontTraits = noteSwiftUIFontTraits(from: noteExplicitSwiftUIFont(from: run.attributes))
        return InlineFormattingState(
            bold: swiftUIFontTraits.bold,
            italic: swiftUIFontTraits.italic,
            underline: run.underlineStyle != nil
        )
    }

    func applyInlineFormattingState(
        _ state: InlineFormattingState,
        to attrs: inout AttributeContainer
    ) {
        let font = inlineStyledFont(bold: state.bold, italic: state.italic)
        setFont(font, in: &attrs)
        attrs.underlineStyle = state.underline ? .single : nil
        attrs.strikethroughStyle = nil
        attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }

    func applyInlineFormattingState(
        _ state: InlineFormattingState,
        to text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        let font = inlineStyledFont(bold: state.bold, italic: state.italic)
        setFont(font, in: &text, range: range)
        text[range].underlineStyle = state.underline ? .single : nil
        text[range].strikethroughStyle = nil
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }
}

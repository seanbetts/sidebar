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
        let blockType = NoteTextBlockAttribute.blockType(from: attrs.noteBlock)
        let traits = noteSemanticInlineFormattingTraits(from: attrs, blockType: blockType)
        return InlineFormattingState(
            bold: traits.bold,
            italic: traits.italic,
            underline: attrs.underlineStyle != nil,
            strikethrough: attrs.strikethroughStyle != nil,
            inlineCode: traits.monospaced
        )
    }

    func inlineFormattingState(from run: AttributedString.Runs.Run) -> InlineFormattingState {
        let traits = noteSemanticInlineFormattingTraits(from: run)
        return InlineFormattingState(
            bold: traits.bold,
            italic: traits.italic,
            underline: run.underlineStyle != nil,
            strikethrough: run.strikethroughStyle != nil,
            inlineCode: traits.monospaced
        )
    }

    func applyInlineFormattingState(
        _ state: InlineFormattingState,
        to attrs: inout AttributeContainer
    ) {
        let font = inlineStyledFont(
            bold: state.bold,
            italic: state.italic,
            monospaced: state.inlineCode
        )
        setFont(font, in: &attrs)
        setPlatformFont(
            inlineStyledPlatformFont(
                bold: state.bold,
                italic: state.italic,
                monospaced: state.inlineCode
            ),
            in: &attrs
        )
        attrs.underlineStyle = state.underline ? .single : nil
        attrs.strikethroughStyle = state.strikethrough ? .single : nil
        attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }

    func applyInlineFormattingState(
        _ state: InlineFormattingState,
        to text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        let font = inlineStyledFont(
            bold: state.bold,
            italic: state.italic,
            monospaced: state.inlineCode
        )
        setFont(font, in: &text, range: range)
        setPlatformFont(
            inlineStyledPlatformFont(
                bold: state.bold,
                italic: state.italic,
                monospaced: state.inlineCode
            ),
            in: &text,
            range: range
        )
        text[range].underlineStyle = state.underline ? .single : nil
        text[range].strikethroughStyle = state.strikethrough ? .single : nil
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }

    func setPlatformFont(_ font: NotePlatformFont, in attrs: inout AttributeContainer) {
        #if os(iOS)
        attrs[AttributeScopes.UIKitAttributes.FontAttribute.self] = font
        #elseif os(macOS)
        attrs[AttributeScopes.AppKitAttributes.FontAttribute.self] = font
        #endif
    }

    func setPlatformFont(
        _ font: NotePlatformFont,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        #if os(iOS)
        text[range][AttributeScopes.UIKitAttributes.FontAttribute.self] = font
        #elseif os(macOS)
        text[range][AttributeScopes.AppKitAttributes.FontAttribute.self] = font
        #endif
    }
}

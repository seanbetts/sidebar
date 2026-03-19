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
        #if os(iOS)
        setPlatformFont(
            inlineStyledPlatformFont(
                bold: state.bold,
                italic: state.italic,
                monospaced: state.inlineCode
            ),
            in: &attrs
        )
        #elseif os(macOS)
        setPlatformFont(
            inlineStyledPlatformFont(
                bold: false,
                italic: false,
                monospaced: state.inlineCode
            ),
            in: &attrs
        )
        #endif
        #if os(iOS)
        attrs[AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] =
            state.inlineCode ? NoteTextAppearance.inlineCodeBackgroundColor : nil
        #elseif os(macOS)
        attrs[AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] =
            state.inlineCode ? NoteTextAppearance.inlineCodeBackgroundColor : nil
        #endif
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
        #if os(iOS)
        setPlatformFont(
            inlineStyledPlatformFont(
                bold: state.bold,
                italic: state.italic,
                monospaced: state.inlineCode
            ),
            in: &text,
            range: range
        )
        #elseif os(macOS)
        setPlatformFont(
            inlineStyledPlatformFont(
                bold: false,
                italic: false,
                monospaced: state.inlineCode
            ),
            in: &text,
            range: range
        )
        #endif
        #if os(iOS)
        text[range][AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] =
            state.inlineCode ? NoteTextAppearance.inlineCodeBackgroundColor : nil
        #elseif os(macOS)
        text[range][AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] =
            state.inlineCode ? NoteTextAppearance.inlineCodeBackgroundColor : nil
        #endif
        text[range].underlineStyle = state.underline ? .single : nil
        text[range].strikethroughStyle = state.strikethrough ? .single : nil
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }

    func applySemanticTypingAttributes(
        blockType: NotesSemanticDocument.BlockType,
        inlineState: InlineFormattingState,
        to attrs: inout AttributeContainer
    ) {
        applyInlineFormattingState(inlineState, to: &attrs)
        attrs.font = noteEditorInlineFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: inlineState.bold,
            italic: inlineState.italic,
            inlineCode: inlineState.inlineCode
        )
        #if os(iOS)
        setPlatformFont(
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: blockType,
                bold: inlineState.bold,
                italic: inlineState.italic,
                inlineCode: inlineState.inlineCode
            ),
            in: &attrs
        )
        #elseif os(macOS)
        setPlatformFont(
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: blockType,
                bold: false,
                italic: false,
                inlineCode: inlineState.inlineCode
            ),
            in: &attrs
        )
        #endif
        attrs.paragraphStyle = paragraphStyle(for: blockType)
        attrs.noteBlock = blockMarker(for: blockType)
        attrs.noteStructuralBoundary = nil
        attrs.link = nil
        attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
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

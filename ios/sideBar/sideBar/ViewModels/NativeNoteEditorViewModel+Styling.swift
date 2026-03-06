@preconcurrency import Foundation
import SwiftUI
#if os(iOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func platformBodyFont() -> PlatformFont {
        notePlatformBodyFont(baseFontSize: baseFontSize)
    }

    func platformSystemFont(
        size: CGFloat,
        weight: PlatformFontWeight,
        monospaced: Bool = false
    ) -> PlatformFont {
        #if os(iOS)
        return monospaced
            ? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        #else
        return monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        #endif
    }

    func platformFontApplyingTraits(
        _ font: PlatformFont,
        bold: Bool,
        italic: Bool
    ) -> PlatformFont {
        notePlatformFont(baseFontSize: font.pointSize, bold: bold, italic: italic)
    }

    func swiftUIFontHasTrait(
        _ font: Font?,
        for intent: InlinePresentationIntent
    ) -> Bool {
        guard let font else { return false }
        let resolved = noteSwiftUIFontTraits(from: font)
        switch intent {
        case .stronglyEmphasized:
            return resolved.bold
        case .emphasized:
            return resolved.italic
        default:
            return false
        }
    }

    func platformColor(_ color: Color) -> PlatformColor {
#if os(iOS)
        UIColor(color)
#else
        NSColor(color)
#endif
    }

    func platformColor(_ color: Color?) -> PlatformColor? {
        guard let color else { return nil }
        return platformColor(color)
    }

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

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
        let swiftUIFontTraits = inlineTraits(from: attrs.font, fallbackAttributes: attrs)
        return InlineFormattingState(
            bold: swiftUIFontTraits.bold,
            italic: swiftUIFontTraits.italic,
            underline: attrs.underlineStyle != nil
        )
    }

    func inlineFormattingState(from run: AttributedString.Runs.Run) -> InlineFormattingState {
        let swiftUIFontTraits = inlineTraits(from: run.font, fallbackAttributes: run.attributes)
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
#if os(macOS)
        var sample = AttributedString("x")
        let sampleRange = sample.startIndex..<sample.endIndex
        sample[sampleRange].mergeAttributes(attrs)
        sample[sampleRange].mergeAttributes(
            notePlatformFontMirrorAttributes(
                baseFontSize: baseFontSize,
                bold: state.bold,
                italic: state.italic
            )
        )
        if let merged = sample.runs.first?.attributes {
            attrs = merged
        }
#endif
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
#if os(macOS)
        text[range].mergeAttributes(
            notePlatformFontMirrorAttributes(
                baseFontSize: baseFontSize,
                bold: state.bold,
                italic: state.italic
            )
        )
#endif
        text[range].underlineStyle = state.underline ? .single : nil
        text[range].strikethroughStyle = nil
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }

    private func inlineTraits(
        from font: Font?,
        fallbackAttributes: AttributeContainer
    ) -> InlineFormattingTraits {
        let traits = noteSwiftUIFontTraits(from: font)
        let fallbackTraits = noteBridgedPlatformFont(from: fallbackAttributes)
            .map(notePlatformFontTraits(from:))
            ?? .plain
        return InlineFormattingTraits(
            bold: traits.bold || fallbackTraits.bold,
            italic: traits.italic || fallbackTraits.italic
        )
    }

    private struct InlineFormattingTraits {
        let bold: Bool
        let italic: Bool

        static let plain = InlineFormattingTraits(bold: false, italic: false)
    }
}

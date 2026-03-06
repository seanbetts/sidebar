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

    func setFont(_ font: Font, platformFont: PlatformFont, in attrs: inout AttributeContainer) {
        attrs.font = font
        setPlatformFont(platformFont, in: &attrs)
    }

    func setFont(
        _ font: Font,
        platformFont: PlatformFont,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range].font = font
        setPlatformFont(platformFont, in: &text, range: range)
    }

    func setPlatformFont(_ font: PlatformFont, in attrs: inout AttributeContainer) {
        noteApplyPlatformFont(font, to: &attrs)
    }

    func setPlatformFont(
        _ font: PlatformFont,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        noteApplyPlatformFont(font, to: &text, range: range)
    }

    func inlineFormattingState(from attrs: AttributeContainer) -> InlineFormattingState {
        let swiftUIFontTraits = inlineTraits(from: attrs.font)
        let platformFontTraits = platformFont(from: attrs).map(inlineTraits(from:)) ?? .plain
        return InlineFormattingState(
            bold: swiftUIFontTraits.bold || platformFontTraits.bold,
            italic: swiftUIFontTraits.italic || platformFontTraits.italic,
            underline: attrs.underlineStyle != nil
        )
    }

    func inlineFormattingState(from run: AttributedString.Runs.Run) -> InlineFormattingState {
        let swiftUIFontTraits = inlineTraits(from: run.font)
        let platformFontTraits = platformFont(from: run).map(inlineTraits(from:)) ?? .plain
        return InlineFormattingState(
            bold: swiftUIFontTraits.bold || platformFontTraits.bold,
            italic: swiftUIFontTraits.italic || platformFontTraits.italic,
            underline: run.underlineStyle != nil
        )
    }

    func applyInlineFormattingState(
        _ state: InlineFormattingState,
        to attrs: inout AttributeContainer
    ) {
        let font = inlineStyledFont(bold: state.bold, italic: state.italic)
        let platformFont = notePlatformFont(
            baseFontSize: baseFontSize,
            bold: state.bold,
            italic: state.italic
        )
        setFont(font, platformFont: platformFont, in: &attrs)
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
        let platformFont = notePlatformFont(
            baseFontSize: baseFontSize,
            bold: state.bold,
            italic: state.italic
        )
        setFont(font, platformFont: platformFont, in: &text, range: range)
        text[range].underlineStyle = state.underline ? .single : nil
        text[range].strikethroughStyle = nil
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }

    private func inlineTraits(from font: Font?) -> InlineFormattingTraits {
        let traits = noteSwiftUIFontTraits(from: font)
        return InlineFormattingTraits(bold: traits.bold, italic: traits.italic)
    }

    private func inlineTraits(from font: PlatformFont) -> InlineFormattingTraits {
        let traits = notePlatformFontTraits(from: font)
        return InlineFormattingTraits(bold: traits.bold, italic: traits.italic)
    }

    private func platformFont(from run: AttributedString.Runs.Run) -> PlatformFont? {
        #if os(iOS)
        if let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] {
            return font
        }
        #elseif os(macOS)
        if let font = run[AttributeScopes.AppKitAttributes.FontAttribute.self] {
            return font
        }
        #endif
        return bridgedPlatformFont(from: run.attributes)
    }

    private func platformFont(from attrs: AttributeContainer) -> PlatformFont? {
        #if os(iOS)
        if let font = attrs[AttributeScopes.UIKitAttributes.FontAttribute.self] {
            return font
        }
        #elseif os(macOS)
        if let font = attrs[AttributeScopes.AppKitAttributes.FontAttribute.self] {
            return font
        }
        #endif
        return bridgedPlatformFont(from: attrs)
    }

    private func bridgedPlatformFont(
        from attributes: AttributeContainer
    ) -> PlatformFont? {
        noteBridgedPlatformFont(from: attributes)
    }

    private struct InlineFormattingTraits {
        let bold: Bool
        let italic: Bool

        static let plain = InlineFormattingTraits(bold: false, italic: false)
    }
}

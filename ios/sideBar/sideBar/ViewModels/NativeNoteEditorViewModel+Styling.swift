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
    func headingKind(for level: Int) -> BlockKind {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        default: return .heading6
        }
    }

    func baseFont(for blockKind: BlockKind?) -> Font {
        if let blockKind, let level = headingLevel(for: blockKind) {
            let size = NoteTextHeadingMetrics.fontSize(for: level, baseFontSize: baseFontSize)
            let weight: Font.Weight = NoteTextHeadingMetrics.isBold(level: level) ? .bold : .semibold
            return .system(size: size, weight: weight)
        }
        switch blockKind {
        case .codeBlock:
            return blockCodeFont
        case .imageCaption:
            return .system(size: NoteTextTypography.footnoteFontSize(baseFontSize: baseFontSize))
        default:
            return bodyFont
        }
    }

    func platformBaseFont(for blockKind: BlockKind?) -> PlatformFont {
        if let blockKind, let level = headingLevel(for: blockKind) {
            let size = NoteTextHeadingMetrics.fontSize(for: level, baseFontSize: baseFontSize)
            let weight: PlatformFontWeight = NoteTextHeadingMetrics.isBold(level: level) ? .bold : .semibold
            return platformSystemFont(size: size, weight: weight)
        }
        switch blockKind {
        case .codeBlock:
            return platformSystemFont(size: inlineCodeFontSize, weight: .regular, monospaced: true)
        case .imageCaption:
            return platformFootnoteFont()
        default:
            return platformSystemFont(size: baseFontSize, weight: .regular)
        }
    }

    func platformInlineCodeFont() -> PlatformFont {
        platformSystemFont(size: inlineCodeFontSize, weight: .regular, monospaced: true)
    }

    func platformFootnoteFont() -> PlatformFont {
        platformSystemFont(
            size: NoteTextTypography.footnoteFontSize(baseFontSize: baseFontSize),
            weight: .regular
        )
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
#if os(iOS)
        guard bold || italic else { return font }
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) } else { traits.remove(.traitBold) }
        if italic { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
        if bold {
            let boldFont = UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
            if italic,
               let descriptor = boldFont.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
                return UIFont(descriptor: descriptor, size: font.pointSize)
            }
            return boldFont
        }
        if italic, let descriptor = font.fontDescriptor.withSymbolicTraits([.traitItalic]) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
        return font
#else
        guard bold || italic else { return font }
        let manager = NSFontManager.shared
        var result = font
        if bold {
            result = manager.convert(result, toHaveTrait: .boldFontMask)
        }
        if italic {
            result = manager.convert(result, toHaveTrait: .italicFontMask)
        }
        return result
#endif
    }

    func swiftUIFontHasTrait(
        _ font: Font?,
        for intent: InlinePresentationIntent
    ) -> Bool {
        guard let font else { return false }
        switch intent {
        case .stronglyEmphasized:
            guard let weight = swiftUIFontWeight(from: font) else { return false }
            return weight >= 0.35
        case .emphasized:
            return swiftUIFontContainsType(named: "ItalicModifier", in: font)
        default:
            return false
        }
    }

    private func swiftUIFontWeight(from font: Font) -> Double? {
        swiftUIFontWeight(in: Mirror(reflecting: font))
    }

    private func swiftUIFontWeight(in mirror: Mirror) -> Double? {
        for child in mirror.children {
            if child.label == "weight",
               let value = swiftUIFontWeightValue(from: child.value) {
                return value
            }
            if let value = swiftUIFontWeight(in: Mirror(reflecting: child.value)) {
                return value
            }
        }
        return nil
    }

    private func swiftUIFontWeightValue(from value: Any) -> Double? {
        if let direct = value as? Double {
            return direct
        }
        if let direct = value as? CGFloat {
            return Double(direct)
        }

        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            if child.label == "some" || child.label == "value" {
                if let nested = swiftUIFontWeightValue(from: child.value) {
                    return nested
                }
            }
        }
        return nil
    }

    private func swiftUIFontContainsType(named needle: String, in font: Font) -> Bool {
        swiftUIFontContainsType(named: needle, in: Mirror(reflecting: font))
    }

    private func swiftUIFontContainsType(named needle: String, in mirror: Mirror) -> Bool {
        if String(describing: mirror.subjectType).contains(needle) {
            return true
        }
        for child in mirror.children
        where swiftUIFontContainsType(named: needle, in: Mirror(reflecting: child.value)) {
            return true
        }
        return false
    }

    func baseForegroundColor(for blockKind: BlockKind?) -> Color {
        switch blockKind {
        case .blockquote, .taskChecked, .htmlBlock, .gallery:
            return DesignTokens.Colors.textSecondary
        case .imageCaption:
            return DesignTokens.Colors.textTertiary
        default:
            return DesignTokens.Colors.textPrimary
        }
    }

    func baseBackgroundColor(for blockKind: BlockKind?) -> Color? {
        switch blockKind {
        case .blockquote:
            return DesignTokens.Colors.muted.opacity(0.45)
        case .codeBlock:
            return Self.noteStyle.codeBlockBackground
        default:
            return nil
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

    func setForegroundColor(_ color: Color, in attrs: inout AttributeContainer) {
        attrs.foregroundColor = color
        setPlatformForegroundColor(platformColor(color), in: &attrs)
    }

    func setBackgroundColor(_ color: Color?, in attrs: inout AttributeContainer) {
        attrs.backgroundColor = color
        setPlatformBackgroundColor(platformColor(color), in: &attrs)
    }

    func setStrikethrough(
        _ enabled: Bool,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        if enabled {
            text[range].strikethroughStyle = .single
        } else {
            text[range].strikethroughStyle = nil
        }
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

    func setForegroundColor(
        _ color: Color,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range].foregroundColor = color
        setPlatformForegroundColor(platformColor(color), in: &text, range: range)
    }

    func setForegroundColor(_ color: Color, range: Range<AttributedString.Index>) {
        setForegroundColor(color, in: &attributedContent, range: range)
    }

    func setBackgroundColor(
        _ color: Color?,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range].backgroundColor = color
        setPlatformBackgroundColor(platformColor(color), in: &text, range: range)
    }

    func setBackgroundColor(_ color: Color?, range: Range<AttributedString.Index>) {
        setBackgroundColor(color, in: &attributedContent, range: range)
    }

    func setPlatformFont(_ font: PlatformFont, in attrs: inout AttributeContainer) {
#if os(iOS)
        attrs[AttributeScopes.UIKitAttributes.FontAttribute.self] = font
#else
        // Keep macOS font state on the SwiftUI `Font` attribute to avoid Sendable warnings on NSFont.
        _ = font
#endif
    }

    func setPlatformForegroundColor(_ color: PlatformColor, in attrs: inout AttributeContainer) {
#if os(iOS)
        attrs[AttributeScopes.UIKitAttributes.ForegroundColorAttribute.self] = color
#else
        attrs[AttributeScopes.AppKitAttributes.ForegroundColorAttribute.self] = color
#endif
    }

    func setPlatformBackgroundColor(_ color: PlatformColor?, in attrs: inout AttributeContainer) {
#if os(iOS)
        attrs[AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] = color
#else
        attrs[AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] = color
#endif
    }

    func setPlatformFont(
        _ font: PlatformFont,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
#if os(iOS)
        text[range][AttributeScopes.UIKitAttributes.FontAttribute.self] = font
#else
        applyMacOSFont(font, to: &text, range: range)
#endif
    }

    func setPlatformForegroundColor(
        _ color: PlatformColor,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
#if os(iOS)
        text[range][AttributeScopes.UIKitAttributes.ForegroundColorAttribute.self] = color
#else
        text[range][AttributeScopes.AppKitAttributes.ForegroundColorAttribute.self] = color
#endif
    }

    func setPlatformBackgroundColor(
        _ color: PlatformColor?,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
#if os(iOS)
        text[range][AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] = color
#else
        text[range][AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] = color
#endif
    }

#if os(macOS)
    private func applyMacOSFont(
        _ font: NSFont,
        to text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        guard !range.isEmpty else { return }
        let string = String(text.characters)
        let lowerCharacterOffset = text.characters.distance(from: text.startIndex, to: range.lowerBound)
        let upperCharacterOffset = text.characters.distance(from: text.startIndex, to: range.upperBound)
        let lowerStringIndex = string.index(string.startIndex, offsetBy: lowerCharacterOffset)
        let upperStringIndex = string.index(string.startIndex, offsetBy: upperCharacterOffset)
        let nsRange = NSRange(
            location: lowerStringIndex.utf16Offset(in: string),
            length: upperStringIndex.utf16Offset(in: string) - lowerStringIndex.utf16Offset(in: string)
        )

        let bridged = (try? NSAttributedString(text, including: \.attributedNoteTextSurface))
            ?? NSAttributedString(text)
        let mutable = NSMutableAttributedString(attributedString: bridged)
        mutable.addAttribute(.font, value: font, range: nsRange)
        text = (try? AttributedString(mutable, including: \.attributedNoteTextSurface))
            ?? AttributedString(mutable)
    }
#endif
}

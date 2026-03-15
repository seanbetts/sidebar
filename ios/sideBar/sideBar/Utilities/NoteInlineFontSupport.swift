import Foundation
import SwiftUI
#if os(iOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
struct NoteInlineFormattingTraits: Equatable {
    var bold: Bool = false
    var italic: Bool = false
    var monospaced: Bool = false

    static let plain = NoteInlineFormattingTraits()
}

#if os(iOS)
typealias NotePlatformFont = UIFont
#elseif os(macOS)
typealias NotePlatformFont = NSFont
#endif

@available(iOS 26.0, macOS 26.0, *)
func noteInlineFont(
    baseFontSize: CGFloat,
    bold: Bool,
    italic: Bool,
    monospaced: Bool = false
) -> Font {
    var font = Font.system(
        size: baseFontSize,
        weight: bold ? .bold : .regular,
        design: monospaced ? .monospaced : .default
    )
    if italic {
        font = font.italic()
    }
    return font
}

@available(iOS 26.0, macOS 26.0, *)
func notePlatformFont(
    baseFontSize: CGFloat,
    bold: Bool,
    italic: Bool,
    monospaced: Bool = false
) -> NotePlatformFont {
    if bold, !italic, !monospaced {
        return notePlatformBoldBodyFont(baseFontSize: baseFontSize)
    }
    return notePlatformFontApplyingTraits(
        notePlatformBodyFont(baseFontSize: baseFontSize, monospaced: monospaced),
        bold: bold,
        italic: italic
    )
}

@available(iOS 26.0, macOS 26.0, *)
func notePlatformFont(
    baseFontSize: CGFloat,
    blockType: NotesSemanticDocument.BlockType,
    bold: Bool,
    italic: Bool,
    inlineCode: Bool = false
) -> NotePlatformFont {
    let baseFont = NoteTextStyleTypography.platformFont(for: blockType, baseFontSize: baseFontSize)
        ?? notePlatformSystemFont(
            size: noteBlockPointSize(baseFontSize: baseFontSize, blockType: blockType),
            weight: .regular,
            monospaced: noteUsesMonospacedDesign(blockType: blockType, inlineCode: inlineCode)
        )
    return notePlatformFontApplyingTraits(
        noteUsesMonospacedDesign(blockType: blockType, inlineCode: inlineCode)
            ? notePlatformSystemFont(
                size: baseFont.pointSize,
                weight: baseFontTraitsWeight(for: baseFont),
                monospaced: true
            )
            : baseFont,
        bold: bold,
        italic: italic
    )
}

@available(iOS 26.0, macOS 26.0, *)
func notePlatformBodyFont(
    baseFontSize: CGFloat,
    monospaced: Bool = false
) -> NotePlatformFont {
    notePlatformSystemFont(size: baseFontSize, weight: .regular, monospaced: monospaced)
}

@available(iOS 26.0, macOS 26.0, *)
func notePlatformBoldBodyFont(baseFontSize: CGFloat) -> NotePlatformFont {
#if os(iOS)
    return UIFont.systemFont(ofSize: baseFontSize, weight: .bold)
#else
    NSFont.boldSystemFont(ofSize: baseFontSize)
#endif
}

@available(iOS 26.0, macOS 26.0, *)
func noteBlockPointSize(
    baseFontSize: CGFloat,
    blockType: NotesSemanticDocument.BlockType
) -> CGFloat {
    guard let style = NoteTextStyle(blockType: blockType) else { return baseFontSize }
    return NoteTextStyleTypography.pointSize(for: style, baseFontSize: baseFontSize)
}

@available(iOS 26.0, macOS 26.0, *)
func noteBlockUsesMonospacedDesign(_ blockType: NotesSemanticDocument.BlockType) -> Bool {
    noteUsesMonospacedDesign(blockType: blockType)
}

@available(iOS 26.0, macOS 26.0, *)
func noteUsesMonospacedDesign(
    blockType: NotesSemanticDocument.BlockType,
    inlineCode: Bool = false
) -> Bool {
    blockType == .codeBlock || inlineCode
}

@available(iOS 26.0, macOS 26.0, *)
private func notePlatformSystemFont(
    size: CGFloat,
    weight: NotePlatformFont.Weight,
    monospaced: Bool = false
) -> NotePlatformFont {
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

@available(iOS 26.0, macOS 26.0, *)
private func notePlatformFontApplyingTraits(
    _ font: NotePlatformFont,
    bold: Bool,
    italic: Bool
) -> NotePlatformFont {
#if os(iOS)
    guard bold || italic else { return font }
    var traits = font.fontDescriptor.symbolicTraits
    if bold { traits.insert(.traitBold) }
    if italic { traits.insert(.traitItalic) }
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
    if bold { result = manager.convert(result, toHaveTrait: .boldFontMask) }
    if italic { result = manager.convert(result, toHaveTrait: .italicFontMask) }
    return result
#endif
}

@available(iOS 26.0, macOS 26.0, *)
private func baseFontTraitsWeight(for font: NotePlatformFont) -> NotePlatformFont.Weight {
#if os(iOS)
    if font.fontDescriptor.symbolicTraits.contains(.traitBold) {
        return .bold
    }
    return .regular
#else
    let traits = NSFontManager.shared.traits(of: font)
    return traits.contains(.boldFontMask) ? .bold : .regular
#endif
}

@available(iOS 26.0, macOS 26.0, *)
func noteSwiftUIFontTraits(from font: Font?) -> NoteInlineFormattingTraits {
    guard let font else { return .plain }
    let resolved = font.resolve(in: EnvironmentValues().fontResolutionContext)
    return NoteInlineFormattingTraits(bold: resolved.isBold, italic: resolved.isItalic)
}

@available(iOS 26.0, macOS 26.0, *)
func noteExplicitSwiftUIFont(from attributes: AttributeContainer) -> Font? {
    attributes[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
}

@available(iOS 26.0, macOS 26.0, *)
func noteInlineFormattingTraits(from attributes: AttributeContainer) -> NoteInlineFormattingTraits {
    var traits = noteSwiftUIFontTraits(from: noteExplicitSwiftUIFont(from: attributes))
    if let platformFont = noteExplicitPlatformFont(from: attributes) {
        let platformTraits = notePlatformFontTraits(from: platformFont)
        traits.bold = traits.bold || platformTraits.bold
        traits.italic = traits.italic || platformTraits.italic
        traits.monospaced = traits.monospaced || platformTraits.monospaced
    }
    return traits
}

@available(iOS 26.0, macOS 26.0, *)
func noteExplicitPlatformFont(from attributes: AttributeContainer) -> NotePlatformFont? {
    #if os(iOS)
    attributes[AttributeScopes.UIKitAttributes.FontAttribute.self]
    #elseif os(macOS)
    attributes[AttributeScopes.AppKitAttributes.FontAttribute.self]
    #endif
}

@available(iOS 26.0, macOS 26.0, *)
func notePlatformFontTraits(from font: NotePlatformFont) -> NoteInlineFormattingTraits {
#if os(iOS)
    return NoteInlineFormattingTraits(
        bold: font.fontDescriptor.symbolicTraits.contains(.traitBold),
        italic: font.fontDescriptor.symbolicTraits.contains(.traitItalic),
        monospaced: font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
    )
#else
    let traitMask = NSFontManager.shared.traits(of: font)
    return NoteInlineFormattingTraits(
        bold: font.fontDescriptor.symbolicTraits.contains(.bold) || traitMask.contains(.boldFontMask),
        italic: font.fontDescriptor.symbolicTraits.contains(.italic) || traitMask.contains(.italicFontMask),
        monospaced: font.fontDescriptor.symbolicTraits.contains(.monoSpace)
    )
#endif
}

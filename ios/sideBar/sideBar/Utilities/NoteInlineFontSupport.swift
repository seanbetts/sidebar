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

    static let plain = NoteInlineFormattingTraits()
}

#if os(iOS)
typealias NotePlatformFont = UIFont
#elseif os(macOS)
typealias NotePlatformFont = NSFont
#endif

@available(iOS 26.0, macOS 26.0, *)
func noteInlineFont(baseFontSize: CGFloat, bold: Bool, italic: Bool) -> Font {
    _ = baseFontSize
    var font = Font.default
    if bold {
        font = font.weight(.bold)
    }
    if italic {
        font = font.italic()
    }
    return font
}

@available(iOS 26.0, macOS 26.0, *)
func notePlatformFont(baseFontSize: CGFloat, bold: Bool, italic: Bool) -> NotePlatformFont {
    notePlatformFontApplyingTraits(
        notePlatformBodyFont(baseFontSize: baseFontSize),
        bold: bold,
        italic: italic
    )
}

@available(iOS 26.0, macOS 26.0, *)
func notePlatformBodyFont(baseFontSize: CGFloat) -> NotePlatformFont {
    notePlatformSystemFont(size: baseFontSize, weight: .regular)
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
    let manager = NSFontManager.shared
    var result = manager.convert(font, toNotHaveTrait: .boldFontMask)
    result = manager.convert(result, toNotHaveTrait: .italicFontMask)
    if bold {
        result = manager.convert(result, toHaveTrait: .boldFontMask)
    }
    if italic {
        result = manager.convert(result, toHaveTrait: .italicFontMask)
    }
    return result
#endif
}

@available(iOS 26.0, macOS 26.0, *)
func noteSwiftUIFontTraits(from font: Font?) -> NoteInlineFormattingTraits {
    guard let font else { return .plain }
    let resolved = font.resolve(in: EnvironmentValues().fontResolutionContext)
    return NoteInlineFormattingTraits(bold: resolved.isBold, italic: resolved.isItalic)
}

@available(iOS 26.0, macOS 26.0, *)
func notePlatformFontTraits(from font: NotePlatformFont) -> NoteInlineFormattingTraits {
#if os(iOS)
    return NoteInlineFormattingTraits(
        bold: font.fontDescriptor.symbolicTraits.contains(.traitBold),
        italic: font.fontDescriptor.symbolicTraits.contains(.traitItalic)
    )
#else
    let traitMask = NSFontManager.shared.traits(of: font)
    return NoteInlineFormattingTraits(
        bold: font.fontDescriptor.symbolicTraits.contains(.bold) || traitMask.contains(.boldFontMask),
        italic: font.fontDescriptor.symbolicTraits.contains(.italic) || traitMask.contains(.italicFontMask)
    )
#endif
}

@available(iOS 26.0, macOS 26.0, *)
func noteApplyPlatformFont(_ font: NotePlatformFont, to attrs: inout AttributeContainer) {
    var sample = AttributedString("x")
    let range = sample.startIndex..<sample.endIndex
    sample[range].mergeAttributes(attrs)
    sample[range].mergeAttributes(notePlatformFontAttributes(font))
    if let merged = sample.runs.first?.attributes {
        attrs = merged
    }
}

@available(iOS 26.0, macOS 26.0, *)
func noteApplyPlatformFont(
    _ font: NotePlatformFont,
    to text: inout AttributedString,
    range: Range<AttributedString.Index>
) {
    text[range].mergeAttributes(notePlatformFontAttributes(font))
}

@available(iOS 26.0, macOS 26.0, *)
func noteBridgedPlatformFont(from attributes: AttributeContainer) -> NotePlatformFont? {
    var sample = AttributedString("x")
    let range = sample.startIndex..<sample.endIndex
    sample[range].mergeAttributes(attributes)
    let bridged = (try? NSAttributedString(sample, including: \.attributedNoteTextSurface))
        ?? NSAttributedString(sample)
    guard bridged.length > 0 else { return nil }
    return bridged.attribute(.font, at: 0, effectiveRange: nil) as? NotePlatformFont
}

@available(iOS 26.0, macOS 26.0, *)
private func notePlatformFontAttributes(_ font: NotePlatformFont) -> AttributeContainer {
    let mutable = NSMutableAttributedString(string: "x")
    mutable.addAttribute(.font, value: font, range: NSRange(location: 0, length: mutable.length))
    let bridged = AttributedString(mutable)
    return bridged.runs.first?.attributes ?? AttributeContainer()
}

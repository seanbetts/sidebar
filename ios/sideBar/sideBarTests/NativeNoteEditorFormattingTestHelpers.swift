import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
@testable import sideBar

@available(iOS 26.0, macOS 26.0, *)
func noteCharacterRange(
    length: Int,
    in text: AttributedString
) -> Range<AttributedString.Index> {
    var index = text.startIndex
    for _ in 0..<length {
        index = text.index(afterCharacter: index)
    }
    return text.startIndex..<index
}

@available(iOS 26.0, macOS 26.0, *)
func noteRunHasBoldTrait(_ run: AttributedString.Runs.Run) -> Bool {
    let resolved = run.font?.resolve(in: EnvironmentValues().fontResolutionContext)
    if resolved?.isBold == true {
        return true
    }
    #if os(iOS)
    guard let font = noteBridgedPlatformFont(from: run) as? UIFont else { return false }
    return font.fontDescriptor.symbolicTraits.contains(.traitBold)
    #elseif os(macOS)
    guard let font = noteBridgedPlatformFont(from: run) as? NSFont else { return false }
    let traitMask = NSFontManager.shared.traits(of: font)
    return font.fontDescriptor.symbolicTraits.contains(.bold) || traitMask.contains(.boldFontMask)
    #endif
}

@available(iOS 26.0, macOS 26.0, *)
func noteRunHasItalicTrait(_ run: AttributedString.Runs.Run) -> Bool {
    let resolved = run.font?.resolve(in: EnvironmentValues().fontResolutionContext)
    if resolved?.isItalic == true {
        return true
    }
    #if os(iOS)
    guard let font = noteBridgedPlatformFont(from: run) as? UIFont else { return false }
    return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
    #elseif os(macOS)
    guard let font = noteBridgedPlatformFont(from: run) as? NSFont else { return false }
    let traitMask = NSFontManager.shared.traits(of: font)
    return font.fontDescriptor.symbolicTraits.contains(.italic) || traitMask.contains(.italicFontMask)
    #endif
}

@available(iOS 26.0, macOS 26.0, *)
func noteRangeHasBoldTrait(
    _ text: AttributedString,
    range: Range<AttributedString.Index>
) -> Bool {
    let runs = text[range].runs
    guard !runs.isEmpty else { return false }
    return runs.allSatisfy(noteRunHasBoldTrait)
}

@available(iOS 26.0, macOS 26.0, *)
func noteRangeHasItalicTrait(
    _ text: AttributedString,
    range: Range<AttributedString.Index>
) -> Bool {
    let runs = text[range].runs
    guard !runs.isEmpty else { return false }
    return runs.allSatisfy(noteRunHasItalicTrait)
}

@available(iOS 26.0, macOS 26.0, *)
func noteRangeHasBridgedBoldPlatformFont(
    _ text: AttributedString,
    range: Range<AttributedString.Index>
) -> Bool {
    let plainText = String(text.characters)
    let nsRange = noteNSRange(for: range, in: text, plainText: plainText)
    let bridged = NSAttributedString(text)
    guard bridged.length > 0, nsRange.length > 0 else { return false }

    var result = true
    bridged.enumerateAttribute(.font, in: nsRange) { value, _, stop in
        #if os(iOS)
        guard let font = value as? UIFont,
              font.fontDescriptor.symbolicTraits.contains(.traitBold) else {
            result = false
            stop.pointee = true
            return
        }
        #elseif os(macOS)
        guard let font = value as? NSFont,
              font.fontDescriptor.symbolicTraits.contains(.bold)
                || NSFontManager.shared.traits(of: font).contains(.boldFontMask) else {
            result = false
            stop.pointee = true
            return
        }
        #endif
    }
    return result
}

@available(iOS 26.0, macOS 26.0, *)
func noteRangeHasBridgedItalicPlatformFont(
    _ text: AttributedString,
    range: Range<AttributedString.Index>
) -> Bool {
    let plainText = String(text.characters)
    let nsRange = noteNSRange(for: range, in: text, plainText: plainText)
    let bridged = NSAttributedString(text)
    guard bridged.length > 0, nsRange.length > 0 else { return false }

    var result = true
    bridged.enumerateAttribute(.font, in: nsRange) { value, _, stop in
        #if os(iOS)
        guard let font = value as? UIFont,
              font.fontDescriptor.symbolicTraits.contains(.traitItalic) else {
            result = false
            stop.pointee = true
            return
        }
        #elseif os(macOS)
        guard let font = value as? NSFont,
              font.fontDescriptor.symbolicTraits.contains(.italic)
                || NSFontManager.shared.traits(of: font).contains(.italicFontMask) else {
            result = false
            stop.pointee = true
            return
        }
        #endif
    }
    return result
}

@available(iOS 26.0, macOS 26.0, *)
func noteRangeIsUnderlined(
    _ text: AttributedString,
    range: Range<AttributedString.Index>
) -> Bool {
    let runs = text[range].runs
    guard !runs.isEmpty else { return false }
    return runs.allSatisfy { $0.underlineStyle == .single }
}

@available(iOS 26.0, macOS 26.0, *)
func noteRangeIsStruckThrough(
    _ text: AttributedString,
    range: Range<AttributedString.Index>
) -> Bool {
    let runs = text[range].runs
    guard !runs.isEmpty else { return false }
    return runs.allSatisfy { $0.strikethroughStyle == .single }
}

@available(iOS 26.0, macOS 26.0, *)
func noteLinkValue(
    in text: AttributedString,
    atCharacterOffset offset: Int
) -> URL? {
    let plainText = String(text.characters)
    guard offset >= 0, offset < plainText.count else { return nil }
    let lower = plainText.index(plainText.startIndex, offsetBy: offset)
    let nsLocation = lower.utf16Offset(in: plainText)
    return NSAttributedString(text).attribute(.link, at: nsLocation, effectiveRange: nil) as? URL
}

@available(iOS 26.0, macOS 26.0, *)
func noteTypingTraits(from attrs: AttributeContainer) -> (bold: Bool, italic: Bool) {
    let resolved = attrs.font?.resolve(in: EnvironmentValues().fontResolutionContext)
    return (resolved?.isBold == true, resolved?.isItalic == true)
}

@available(iOS 26.0, macOS 26.0, *)
func noteBridgedPlatformFont(from run: AttributedString.Runs.Run) -> AnyObject? {
    var sample = AttributedString("x")
    let range = sample.startIndex..<sample.endIndex
    sample[range].mergeAttributes(run.attributes)
    let bridged = (try? NSAttributedString(sample, including: \.noteTextEditor))
        ?? NSAttributedString(sample)
    return bridged.attribute(NSAttributedString.Key.font, at: 0, effectiveRange: nil) as AnyObject?
}

@available(iOS 26.0, macOS 26.0, *)
private func noteNSRange(
    for range: Range<AttributedString.Index>,
    in text: AttributedString,
    plainText: String
) -> NSRange {
    let lowerCharacterOffset = text.characters.distance(from: text.startIndex, to: range.lowerBound)
    let upperCharacterOffset = text.characters.distance(from: text.startIndex, to: range.upperBound)
    let lower = plainText.index(plainText.startIndex, offsetBy: lowerCharacterOffset)
    let upper = plainText.index(plainText.startIndex, offsetBy: upperCharacterOffset)
    return NSRange(
        location: lower.utf16Offset(in: plainText),
        length: upper.utf16Offset(in: plainText) - lower.utf16Offset(in: plainText)
    )
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func noteAppendTypedText(_ string: String, to viewModel: NativeNoteEditorViewModel) {
    var inserted = AttributedString(string)
    let range = inserted.startIndex..<inserted.endIndex
    inserted[range].mergeAttributes(
        viewModel.selection.typingAttributes(in: viewModel.attributedContent)
    )
    let insertion = viewModel.attributedContent.endIndex
    viewModel.attributedContent.insert(inserted, at: insertion)
    let cursor = viewModel.attributedContent.endIndex
    viewModel.selection = AttributedTextSelection(range: cursor..<cursor)
}

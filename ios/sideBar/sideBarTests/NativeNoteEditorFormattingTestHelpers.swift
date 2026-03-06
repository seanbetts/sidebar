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
func noteFirstRunPointSize(in text: AttributedString) -> CGFloat? {
    for run in text.runs {
        #if os(iOS)
        if let font = noteBridgedPlatformFont(from: run) as? UIFont {
            return font.pointSize
        }
        #elseif os(macOS)
        if let font = noteBridgedPlatformFont(from: run) as? NSFont {
            return font.pointSize
        }
        #endif
    }
    return nil
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
    return font.fontDescriptor.symbolicTraits.contains(.bold)
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
    return font.fontDescriptor.symbolicTraits.contains(.italic)
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
func noteRangeIsUnderlined(
    _ text: AttributedString,
    range: Range<AttributedString.Index>
) -> Bool {
    let runs = text[range].runs
    guard !runs.isEmpty else { return false }
    return runs.allSatisfy { $0.underlineStyle == .single }
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
    let bridged = (try? NSAttributedString(sample, including: \.attributedNoteTextSurface))
        ?? NSAttributedString(sample)
    return bridged.attribute(NSAttributedString.Key.font, at: 0, effectiveRange: nil) as AnyObject?
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

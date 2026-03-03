import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
func bridgeToNSAttributedString(_ text: AttributedString) -> NSAttributedString {
    if let scoped = try? NSAttributedString(text, including: \.attributedNoteTextSurface) {
        return scoped
    }
    return NSAttributedString(text)
}

@available(iOS 26.0, macOS 26.0, *)
func bridgeToAttributedString(_ text: NSAttributedString) -> AttributedString {
    if let scoped = try? AttributedString(text, including: \.attributedNoteTextSurface) {
        return scoped
    }
    return AttributedString(text)
}

@available(iOS 26.0, macOS 26.0, *)
func nsRange(from selection: AttributedTextSelection, in text: AttributedString) -> NSRange {
    let string = String(text.characters)
    switch selection.indices(in: text) {
    case .insertionPoint(let index):
        let characterOffset = text.characters.distance(from: text.startIndex, to: index)
        let stringIndex = string.index(string.startIndex, offsetBy: characterOffset)
        let location = stringIndex.utf16Offset(in: string)
        return NSRange(location: location, length: 0)
    case .ranges(let ranges):
        guard let first = ranges.ranges.first else {
            return NSRange(location: 0, length: 0)
        }
        let lowerOffset = text.characters.distance(from: text.startIndex, to: first.lowerBound)
        let upperOffset = text.characters.distance(from: text.startIndex, to: first.upperBound)
        let lowerIndex = string.index(string.startIndex, offsetBy: lowerOffset)
        let upperIndex = string.index(string.startIndex, offsetBy: upperOffset)
        let location = lowerIndex.utf16Offset(in: string)
        let length = upperIndex.utf16Offset(in: string) - location
        return NSRange(location: location, length: max(0, length))
    }
}

@available(iOS 26.0, macOS 26.0, *)
func selectionFromRange(_ range: NSRange, in text: AttributedString) -> AttributedTextSelection {
    let string = String(text.characters)
    let maxLocation = string.utf16.count
    let safeLocation = min(max(0, range.location), maxLocation)
    let safeEnd = min(max(0, range.location + range.length), maxLocation)
    let startIndex = String.Index(utf16Offset: safeLocation, in: string)
    let endIndex = String.Index(utf16Offset: safeEnd, in: string)
    let startOffset = string.distance(from: string.startIndex, to: startIndex)
    let endOffset = string.distance(from: string.startIndex, to: endIndex)
    let start = text.index(text.startIndex, offsetByCharacters: startOffset)
    let end = text.index(text.startIndex, offsetByCharacters: endOffset)
    if start == end {
        return AttributedTextSelection(range: start..<start)
    }
    return AttributedTextSelection(range: start..<end)
}

@available(iOS 26.0, macOS 26.0, *)
func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(max(range.location, 0), maxLength)
    let safeLength = min(max(range.length, 0), max(0, maxLength - safeLocation))
    return NSRange(location: safeLocation, length: safeLength)
}

@available(iOS 26.0, macOS 26.0, *)
func typingAttributesDictionary(
    from attributes: AttributeContainer
) -> [NSAttributedString.Key: Any] {
    var sample = AttributedString("x")
    let range = sample.startIndex..<sample.endIndex
    sample[range].mergeAttributes(attributes)
    let bridged = bridgeToNSAttributedString(sample)
    guard bridged.length > 0 else { return [:] }
    return bridged.attributes(at: 0, effectiveRange: nil)
}

@available(iOS 26.0, macOS 26.0, *)
func resolvedTypingAttributes(
    text: AttributedString,
    selectionTypingAttributes: AttributeContainer,
    fallbackTypingAttributes: AttributeContainer
) -> AttributeContainer {
    var resolved = selectionTypingAttributes
    if text.characters.isEmpty {
        if resolved.blockKind == nil {
            resolved.blockKind = fallbackTypingAttributes.blockKind
        }
        if resolved.paragraphStyle == nil {
            resolved.paragraphStyle = fallbackTypingAttributes.paragraphStyle
        }
        if resolved.font == nil {
            resolved.font = fallbackTypingAttributes.font
        }
        return resolved
    }

    if resolved.blockKind == nil {
        resolved.blockKind = fallbackTypingAttributes.blockKind
    }
    if resolved.paragraphStyle == nil {
        resolved.paragraphStyle = fallbackTypingAttributes.paragraphStyle
    }
    if resolved.font == nil {
        resolved.font = fallbackTypingAttributes.font
    }
    return resolved
}

#if os(iOS)
@available(iOS 26.0, *)
func clampedContentOffset(_ offset: CGPoint, in textView: UITextView) -> CGPoint {
    let inset = textView.adjustedContentInset
    let minX = -inset.left
    let minY = -inset.top
    let maxX = max(minX, textView.contentSize.width - textView.bounds.width + inset.right)
    let maxY = max(minY, textView.contentSize.height - textView.bounds.height + inset.bottom)
    return CGPoint(
        x: min(max(offset.x, minX), maxX),
        y: min(max(offset.y, minY), maxY)
    )
}

@available(iOS 26.0, *)
func tappedInsertionRange(in textView: UITextView, location: CGPoint) -> NSRange {
    let length = textView.attributedText.length
    guard length > 0 else {
        return NSRange(location: 0, length: 0)
    }
    if let position = textView.closestPosition(to: location) {
        let offset = textView.offset(from: textView.beginningOfDocument, to: position)
        let clamped = min(max(0, offset), length)
        return NSRange(location: clamped, length: 0)
    }
    return clampedRange(textView.selectedRange, maxLength: length)
}
#elseif os(macOS)
@available(macOS 26.0, *)
func clampedContentOrigin(_ origin: CGPoint, in scrollView: NSScrollView) -> CGPoint {
    guard let documentView = scrollView.documentView else {
        return origin
    }
    let contentBounds = scrollView.contentView.bounds
    let maxX = max(0, documentView.bounds.width - contentBounds.width)
    let maxY = max(0, documentView.bounds.height - contentBounds.height)
    return CGPoint(
        x: min(max(origin.x, 0), maxX),
        y: min(max(origin.y, 0), maxY)
    )
}
#endif

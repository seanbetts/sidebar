import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
func displayText(for text: AttributedString, isEditable: Bool) -> NSAttributedString {
    CodeBlockAttachmentBuilder.displayText(
        from: text,
        renderCodeBlocks: !isEditable,
        renderHorizontalRules: !isEditable
    )
}

@available(iOS 26.0, macOS 26.0, *)
func nsRange(from selection: AttributedTextSelection, in text: AttributedString) -> NSRange {
    let string = String(text.characters)
    switch selection.indices(in: text) {
    case .insertionPoint(let index):
        let charOffset = text.characters.distance(from: text.startIndex, to: index)
        let stringIndex = string.index(string.startIndex, offsetBy: charOffset)
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

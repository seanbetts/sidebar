@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func selectionRanges() -> RangeSet<AttributedString.Index> {
        switch selection.indices(in: attributedContent) {
        case .insertionPoint(let index):
            return RangeSet([index..<index])
        case .ranges(let ranges):
            return ranges
        }
    }

    enum SelectionSnapshot {
        case insertionPoint(Int)
        case ranges([Range<Int>])
    }

    struct LineInfo {
        let range: Range<Int>
        let text: String
    }

    func selectionSnapshot(in text: AttributedString) -> SelectionSnapshot {
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            let offset = text.characters.distance(from: text.startIndex, to: index)
            return .insertionPoint(offset)
        case .ranges(let ranges):
            let offsets = ranges.ranges.map { range in
                let lower = text.characters.distance(from: text.startIndex, to: range.lowerBound)
                let upper = text.characters.distance(from: text.startIndex, to: range.upperBound)
                return lower..<upper
            }
            return .ranges(offsets)
        }
    }

    func selection(from snapshot: SelectionSnapshot, in text: AttributedString) -> AttributedTextSelection {
        let maxOffset = text.characters.count
        func index(for offset: Int) -> AttributedString.Index {
            let clamped = min(max(offset, 0), maxOffset)
            return text.index(text.startIndex, offsetByCharacters: clamped)
        }

        switch snapshot {
        case .insertionPoint(let offset):
            let index = index(for: offset)
            return AttributedTextSelection(range: index..<index)
        case .ranges(let offsets):
            let ranges = offsets.map { range -> Range<AttributedString.Index> in
                let lower = index(for: range.lowerBound)
                let upper = index(for: range.upperBound)
                return lower..<upper
            }
            return AttributedTextSelection(ranges: RangeSet(ranges))
        }
    }

    func transformSelectionAttributes(_ update: (inout AttributeContainer) -> Void) {
        var updatedSelection = selection
        attributedContent.transformAttributes(in: &updatedSelection, body: update)
        if selection != updatedSelection {
            selection = updatedSelection
        }
    }

    func attributedRange(
        for offsets: Range<Int>,
        in text: AttributedString
    ) -> Range<AttributedString.Index> {
        let lower = text.index(text.startIndex, offsetByCharacters: offsets.lowerBound)
        let upper = text.index(text.startIndex, offsetByCharacters: offsets.upperBound)
        return lower..<upper
    }

    func lineRangeIncludingTrailingNewline(
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>
    ) -> Range<AttributedString.Index> {
        var upper = lineRange.upperBound
        if upper < text.endIndex, text.characters[upper].isNewline {
            upper = text.index(afterCharacter: upper)
        }
        return lineRange.lowerBound..<upper
    }

    func selectionLineSpan(in text: AttributedString) -> ClosedRange<Int>? {
        func lineNumber(for index: AttributedString.Index) -> Int {
            var line = 0
            var cursor = text.startIndex
            while cursor < index {
                if text.characters[cursor].isNewline {
                    line += 1
                }
                cursor = text.index(afterCharacter: cursor)
            }
            return line
        }

        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            let line = lineNumber(for: index)
            return line...line
        case .ranges(let ranges):
            let concreteRanges = ranges.ranges
            guard !concreteRanges.isEmpty else { return nil }

            var minLine: Int?
            var maxLine: Int?
            for range in concreteRanges {
                let lowerLine = lineNumber(for: range.lowerBound)
                let upperLine: Int
                if range.isEmpty {
                    upperLine = lowerLine
                } else {
                    let lastIndex = text.index(beforeCharacter: range.upperBound)
                    upperLine = lineNumber(for: lastIndex)
                }
                minLine = min(minLine ?? lowerLine, lowerLine)
                maxLine = max(maxLine ?? upperLine, upperLine)
            }

            guard let minLine, let maxLine else { return nil }
            return minLine...maxLine
        }
    }

}

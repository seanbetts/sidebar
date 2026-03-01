@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModel {
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
        selection = updatedSelection
    }

}

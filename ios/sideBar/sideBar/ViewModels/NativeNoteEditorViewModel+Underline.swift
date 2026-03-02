@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func toggleUnderline() {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            transformSelectionAttributes { attrs in
                attrs.underlineStyle = attrs.underlineStyle == nil ? .single : nil
            }
            return
        }

        let shouldEnable = nonEmptyRanges.contains { range in
            attributedContent[range].underlineStyle == nil
        }
        for range in nonEmptyRanges {
            attributedContent[range].underlineStyle = shouldEnable ? .single : nil
        }
    }

    func isUnderlineActive() -> Bool {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        if !nonEmptyRanges.isEmpty {
            return nonEmptyRanges.allSatisfy { range in
                let runs = attributedContent[range].runs
                guard !runs.isEmpty else { return false }
                return runs.allSatisfy { $0.underlineStyle != nil }
            }
        }

        if selection.typingAttributes(in: attributedContent).underlineStyle != nil {
            return true
        }

        let insertionIndex: AttributedString.Index?
        switch selection.indices(in: attributedContent) {
        case .insertionPoint(let index):
            insertionIndex = index
        case .ranges(let ranges):
            insertionIndex = ranges.ranges.first?.lowerBound
        }
        guard let insertionIndex,
              insertionIndex > attributedContent.startIndex else {
            return false
        }
        let previousIndex = attributedContent.index(beforeCharacter: insertionIndex)
        let previousRange = previousIndex..<insertionIndex
        return attributedContent[previousRange].underlineStyle != nil
    }
}

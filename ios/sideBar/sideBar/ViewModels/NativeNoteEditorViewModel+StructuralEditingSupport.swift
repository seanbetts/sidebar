@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func primarySelectionCharacterRange(in text: AttributedString) -> Range<Int>? {
        let selectionRanges = selectionCharacterRanges(in: text)
        guard selectionRanges.count == 1 else { return nil }
        return selectionRanges.first
    }

    func rangesOverlap(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    func blockInfoContainingCharacterOffset(
        _ offset: Int,
        in document: NotesSemanticDocument
    ) -> DocumentBlockInfo? {
        let infos = documentBlockInfos(in: document)
        guard let lastInfo = infos.last else { return nil }

        if offset >= lastInfo.coverageRange.upperBound {
            return lastInfo
        }

        return infos.first { info in
            if info.coverageRange.isEmpty {
                return offset == info.coverageRange.lowerBound
            }
            return info.coverageRange.contains(offset)
        }
    }
}

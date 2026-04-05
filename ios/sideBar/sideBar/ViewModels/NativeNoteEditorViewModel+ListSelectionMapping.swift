@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    struct ListToggleLineDescriptor {
        let visiblePrefixLength: Int
        let logicalTextLength: Int
    }

    func remappedSelectionSnapshotForListToggle(
        _ snapshot: SelectionSnapshot,
        oldBlocks: [NotesSemanticDocument.Block],
        oldRegionStart: Int,
        newBlocks: [NotesSemanticDocument.Block],
        newRegionStart: Int
    ) -> SelectionSnapshot {
        let oldDescriptors = listToggleLineDescriptors(for: oldBlocks)
        let newDescriptors = listToggleLineDescriptors(for: newBlocks)
        guard !oldDescriptors.isEmpty, !newDescriptors.isEmpty else { return snapshot }

        switch snapshot {
        case .insertionPoint(let offset):
            let localOffset = max(0, offset - oldRegionStart)
            let logicalOffset = logicalOffsetForVisibleListToggleOffset(
                localOffset,
                descriptors: oldDescriptors
            )
            let newLocalOffset = visibleOffsetForLogicalListToggleOffset(
                logicalOffset,
                descriptors: newDescriptors
            )
            return .insertionPoint(newRegionStart + newLocalOffset)
        case .ranges(let ranges):
            let updatedRanges = ranges.map { range in
                let lowerLogicalOffset = logicalOffsetForVisibleListToggleOffset(
                    max(0, range.lowerBound - oldRegionStart),
                    descriptors: oldDescriptors
                )
                let upperLogicalOffset = logicalOffsetForVisibleListToggleOffset(
                    max(0, range.upperBound - oldRegionStart),
                    descriptors: oldDescriptors
                )
                let newLowerOffset = visibleOffsetForLogicalListToggleOffset(
                    lowerLogicalOffset,
                    descriptors: newDescriptors
                )
                let newUpperOffset = visibleOffsetForLogicalListToggleOffset(
                    upperLogicalOffset,
                    descriptors: newDescriptors
                )
                return (newRegionStart + newLowerOffset)..<(newRegionStart + newUpperOffset)
            }
            return .ranges(updatedRanges)
        }
    }

    func listToggleLineDescriptors(
        for blocks: [NotesSemanticDocument.Block]
    ) -> [ListToggleLineDescriptor] {
        blocks.flatMap { block in
            let visibleLines = blockPlainText(block).split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).map(String.init)
            let logicalLines = listToggleLogicalLines(for: block)
            guard visibleLines.count == logicalLines.count else {
                return [ListToggleLineDescriptor]()
            }
            return zip(visibleLines, logicalLines).map { visibleLine, logicalLine in
                ListToggleLineDescriptor(
                    visiblePrefixLength: max(0, visibleLine.count - logicalLine.count),
                    logicalTextLength: logicalLine.count
                )
            }
        }
    }

    func listToggleLogicalLines(
        for block: NotesSemanticDocument.Block
    ) -> [String] {
        switch block.type {
        case .divider:
            return []
        case .paragraph, .title, .heading, .subheading, .codeBlock, .listItem:
            return listToggleLogicalLines(from: block.content)
        case .orderedList, .unorderedList, .checklist, .blockquote:
            return (block.children ?? []).flatMap(listToggleLogicalLines(for:))
        default:
            return []
        }
    }

    func listToggleLogicalLines(
        from content: [NotesSemanticDocument.InlineSegment]
    ) -> [String] {
        let text = content.map(\.text).joined()
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    func logicalOffsetForVisibleListToggleOffset(
        _ visibleOffset: Int,
        descriptors: [ListToggleLineDescriptor]
    ) -> Int {
        var clampedVisibleOffset = max(
            0,
            min(visibleOffset, totalVisibleLengthForListToggle(descriptors: descriptors))
        )
        var logicalOffset = 0

        for (index, descriptor) in descriptors.enumerated() {
            let prefixLength = descriptor.visiblePrefixLength
            let textLength = descriptor.logicalTextLength

            if clampedVisibleOffset <= prefixLength {
                return logicalOffset
            }
            clampedVisibleOffset -= prefixLength

            if clampedVisibleOffset <= textLength {
                return logicalOffset + clampedVisibleOffset
            }
            clampedVisibleOffset -= textLength
            logicalOffset += textLength

            if index < descriptors.count - 1 {
                if clampedVisibleOffset <= 1 {
                    return logicalOffset + clampedVisibleOffset
                }
                clampedVisibleOffset -= 1
                logicalOffset += 1
            }
        }

        return logicalOffset
    }

    func visibleOffsetForLogicalListToggleOffset(
        _ logicalOffset: Int,
        descriptors: [ListToggleLineDescriptor]
    ) -> Int {
        var remainingLogicalOffset = max(
            0,
            min(logicalOffset, totalLogicalLengthForListToggle(descriptors: descriptors))
        )
        var visibleOffset = 0

        for (index, descriptor) in descriptors.enumerated() {
            visibleOffset += descriptor.visiblePrefixLength

            if remainingLogicalOffset <= descriptor.logicalTextLength {
                return visibleOffset + remainingLogicalOffset
            }

            remainingLogicalOffset -= descriptor.logicalTextLength
            visibleOffset += descriptor.logicalTextLength

            if index < descriptors.count - 1 {
                if remainingLogicalOffset <= 1 {
                    return visibleOffset + remainingLogicalOffset
                }
                remainingLogicalOffset -= 1
                visibleOffset += 1
            }
        }

        return visibleOffset
    }

    func totalVisibleLengthForListToggle(
        descriptors: [ListToggleLineDescriptor]
    ) -> Int {
        descriptors.enumerated().reduce(0) { total, element in
            let (index, descriptor) = element
            let newlineLength = index < descriptors.count - 1 ? 1 : 0
            return total + descriptor.visiblePrefixLength + descriptor.logicalTextLength + newlineLength
        }
    }

    func totalLogicalLengthForListToggle(
        descriptors: [ListToggleLineDescriptor]
    ) -> Int {
        descriptors.enumerated().reduce(0) { total, element in
            let (index, descriptor) = element
            let newlineLength = index < descriptors.count - 1 ? 1 : 0
            return total + descriptor.logicalTextLength + newlineLength
        }
    }
}

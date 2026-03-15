import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension NotesAttributedDocumentCodec {
    static func appendDecodedSegmentText(
        _ text: String,
        marks: [NotesSemanticDocument.InlineMark],
        link: NotesSemanticDocument.Link?,
        currentSegments: inout [NotesSemanticDocument.InlineSegment]
    ) {
        guard !text.isEmpty else { return }
        if let last = currentSegments.last,
           last.marks == marks,
           last.link == link {
            currentSegments[currentSegments.count - 1] = .init(
                text: last.text + text,
                marks: last.marks,
                link: last.link
            )
        } else {
            currentSegments.append(.init(text: text, marks: marks, link: link))
        }
    }

    static func flushDecodedBlock(
        blocks: inout [NotesSemanticDocument.Block],
        currentSegments: inout [NotesSemanticDocument.InlineSegment],
        currentBlockMarker: inout String?
    ) {
        let explicitBlockType = NoteTextBlockAttribute.blockType(from: currentBlockMarker)
        let resolvedBlockType = resolvedDecodedBlockType(
            explicitBlockType: explicitBlockType,
            hasExistingBlocks: !blocks.isEmpty
        )
        let normalized = normalizedSegmentsAndCheckedState(
            from: currentSegments,
            blockType: resolvedBlockType
        )
        var segments = normalized.segments
        if segments.isEmpty {
            segments = [NotesSemanticDocument.InlineSegment(text: "", marks: [])]
        }
        blocks.append(
            .init(
                type: resolvedBlockType,
                content: segments,
                checked: normalized.checked
            )
        )
        currentSegments.removeAll(keepingCapacity: true)
        currentBlockMarker = nil
    }

    static func resolvedDecodedBlockType(
        explicitBlockType: NotesSemanticDocument.BlockType?,
        hasExistingBlocks: Bool
    ) -> NotesSemanticDocument.BlockType {
        guard hasExistingBlocks else {
            switch explicitBlockType {
            case .none, .title, .paragraph, .heading, .subheading:
                return .title
            case .some(let explicitBlockType):
                return explicitBlockType
            }
        }
        return explicitBlockType ?? .paragraph
    }
}

import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension NotesAttributedDocumentCodec {
    static func document(from attributed: AttributedString) -> NotesSemanticDocument {
        var blocks: [NotesSemanticDocument.Block] = []
        var currentSegments: [NotesSemanticDocument.InlineSegment] = []
        var currentBlockMarker: String?
        var endedWithStructuralNewline = false

        for run in attributed.runs {
            processDecodedRun(
                run,
                in: attributed,
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker,
                endedWithStructuralNewline: &endedWithStructuralNewline
            )
        }

        if shouldFlushTrailingDecodedBlock(
            blocks: blocks,
            currentSegments: currentSegments,
            endedWithStructuralNewline: endedWithStructuralNewline
        ) {
            flushDecodedBlock(
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker
            )
        }

        return NotesSemanticDocument(blocks: blocks)
    }

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

    static func shouldFlushTrailingDecodedBlock(
        blocks: [NotesSemanticDocument.Block],
        currentSegments: [NotesSemanticDocument.InlineSegment],
        endedWithStructuralNewline: Bool
    ) -> Bool {
        blocks.isEmpty || !currentSegments.isEmpty || endedWithStructuralNewline
    }

    static func processDecodedRun(
        _ run: AttributedString.Runs.Run,
        in attributed: AttributedString,
        blocks: inout [NotesSemanticDocument.Block],
        currentSegments: inout [NotesSemanticDocument.InlineSegment],
        currentBlockMarker: inout String?,
        endedWithStructuralNewline: inout Bool
    ) {
        let blockMarker = run.noteBlock
        let runText = String(attributed[run.range].characters)
        if shouldFlushCodeBlockBeforeSeparatorRun(
            currentBlockMarker: currentBlockMarker,
            blockMarker: blockMarker,
            runText: runText,
            hasBufferedContent: !currentSegments.isEmpty
        ) {
            flushDecodedBlock(
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker
            )
            return
        }

        if shouldFlushBeforeProcessingRun(
            currentBlockMarker: currentBlockMarker,
            blockMarker: blockMarker,
            hasBufferedContent: !currentSegments.isEmpty
        ) {
            flushDecodedBlock(
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker
            )
        }

        if currentBlockMarker == nil || (!currentSegments.isEmpty && blockMarker != nil) {
            currentBlockMarker = blockMarker
        }

        let marks = inlineMarks(from: run)
        let link = semanticLink(from: run)
        let resolvedBlockType = NoteTextBlockAttribute.blockType(
            from: blockMarker ?? currentBlockMarker
        )
        var buffer = ""

        for character in attributed[run.range].characters {
            if character.isNewline {
                if resolvedBlockType == .codeBlock {
                    buffer.append(character)
                    endedWithStructuralNewline = false
                } else {
                    appendDecodedSegmentText(
                        buffer,
                        marks: marks,
                        link: link,
                        currentSegments: &currentSegments
                    )
                    buffer.removeAll(keepingCapacity: true)
                    flushDecodedBlock(
                        blocks: &blocks,
                        currentSegments: &currentSegments,
                        currentBlockMarker: &currentBlockMarker
                    )
                    endedWithStructuralNewline = true
                }
            } else {
                buffer.append(character)
                endedWithStructuralNewline = false
            }
        }

        appendDecodedSegmentText(
            buffer,
            marks: marks,
            link: link,
            currentSegments: &currentSegments
        )
        if !buffer.isEmpty {
            endedWithStructuralNewline = false
        }
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

import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension NotesAttributedDocumentCodec {
    static func document(from attributed: AttributedString) -> NotesSemanticDocument {
        var blocks: [NotesSemanticDocument.Block] = []
        var currentSegments: [NotesSemanticDocument.InlineSegment] = []
        var currentBlockMarker: String?
        var pendingBoundaryMarker: String?
        var pendingBoundaryCount = 0
        var endedWithStructuralNewline = false

        for run in attributed.runs {
            processDecodedRun(
                run,
                in: attributed,
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker,
                pendingBoundaryMarker: &pendingBoundaryMarker,
                pendingBoundaryCount: &pendingBoundaryCount,
                endedWithStructuralNewline: &endedWithStructuralNewline
            )
        }

        if pendingBoundaryCount > 0 {
            flushPendingStructuralBoundaries(
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker,
                pendingBoundaryMarker: &pendingBoundaryMarker,
                pendingBoundaryCount: &pendingBoundaryCount,
                followedByContent: false
            )
            endedWithStructuralNewline = false
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

        return NotesSemanticDocument(blocks: groupedDecodedBlocks(from: blocks))
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
        pendingBoundaryMarker: inout String?,
        pendingBoundaryCount: inout Int,
        endedWithStructuralNewline: inout Bool
    ) {
        let blockMarker = run.noteBlock ?? presentationIntentBlockMarker(from: run)
        let runText = String(attributed[run.range].characters)
        if handleStructuralBoundaryRun(
            blockMarker: blockMarker,
            runText: runText,
            isStructuralBoundaryRun: run.noteStructuralBoundary == true && runText.allSatisfy(\.isNewline),
            blocks: &blocks,
            currentSegments: &currentSegments,
            currentBlockMarker: &currentBlockMarker,
            pendingBoundaryMarker: &pendingBoundaryMarker,
            pendingBoundaryCount: &pendingBoundaryCount,
            endedWithStructuralNewline: &endedWithStructuralNewline
        ) {
            return
        }

        if pendingBoundaryCount > 0 {
            flushPendingStructuralBoundaries(
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker,
                pendingBoundaryMarker: &pendingBoundaryMarker,
                pendingBoundaryCount: &pendingBoundaryCount,
                followedByContent: true
            )
            endedWithStructuralNewline = false
        }

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

        let resolvedBlockType = NoteTextBlockAttribute.blockType(
            from: blockMarker ?? currentBlockMarker
        )
        let marks = inlineMarks(from: run, blockType: resolvedBlockType)
        let link = semanticLink(from: run)
        decodeRunCharacters(
            attributed[run.range].characters,
            marks: marks,
            link: link,
            resolvedBlockType: resolvedBlockType,
            blocks: &blocks,
            currentSegments: &currentSegments,
            currentBlockMarker: &currentBlockMarker,
            endedWithStructuralNewline: &endedWithStructuralNewline
        )
    }

    static func resolvedDecodedBlockType(
        explicitBlockType: NotesSemanticDocument.BlockType?,
        hasExistingBlocks: Bool
    ) -> NotesSemanticDocument.BlockType {
        NoteTextBlockResolution.resolvedDecodedBlockType(
            explicitBlockType: explicitBlockType,
            hasExistingBlocks: hasExistingBlocks
        )
    }

    static func flushPendingStructuralBoundaries(
        blocks: inout [NotesSemanticDocument.Block],
        currentSegments: inout [NotesSemanticDocument.InlineSegment],
        currentBlockMarker: inout String?,
        pendingBoundaryMarker: inout String?,
        pendingBoundaryCount: inout Int,
        followedByContent: Bool
    ) {
        guard pendingBoundaryCount > 0 else { return }
        let blockMarker = pendingBoundaryMarker
        let emptyBlockCount = followedByContent ? max(0, pendingBoundaryCount - 1) : pendingBoundaryCount

        for _ in 0..<emptyBlockCount {
            currentBlockMarker = blockMarker
            flushDecodedBlock(
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker
            )
        }

        currentBlockMarker = followedByContent ? blockMarker : nil
        pendingBoundaryMarker = nil
        pendingBoundaryCount = 0
    }

    static func handleStructuralBoundaryRun(
        blockMarker: String?,
        runText: String,
        isStructuralBoundaryRun: Bool,
        blocks: inout [NotesSemanticDocument.Block],
        currentSegments: inout [NotesSemanticDocument.InlineSegment],
        currentBlockMarker: inout String?,
        pendingBoundaryMarker: inout String?,
        pendingBoundaryCount: inout Int,
        endedWithStructuralNewline: inout Bool
    ) -> Bool {
        guard isStructuralBoundaryRun else { return false }
        if !currentSegments.isEmpty {
            flushDecodedBlock(
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker
            )
        }
        if pendingBoundaryCount > 0, pendingBoundaryMarker != blockMarker {
            flushPendingStructuralBoundaries(
                blocks: &blocks,
                currentSegments: &currentSegments,
                currentBlockMarker: &currentBlockMarker,
                pendingBoundaryMarker: &pendingBoundaryMarker,
                pendingBoundaryCount: &pendingBoundaryCount,
                followedByContent: false
            )
        }
        if pendingBoundaryMarker != blockMarker {
            pendingBoundaryMarker = blockMarker
            pendingBoundaryCount = 0
        }
        pendingBoundaryCount += runText.count
        endedWithStructuralNewline = true
        return true
    }

    static func groupedDecodedBlocks(
        from blocks: [NotesSemanticDocument.Block]
    ) -> [NotesSemanticDocument.Block] {
        var grouped: [NotesSemanticDocument.Block] = []
        var index = 0

        while index < blocks.count {
            let block = blocks[index]
            switch block.type {
            case .orderedList, .unorderedList:
                var children: [NotesSemanticDocument.Block] = []
                while index < blocks.count, blocks[index].type == block.type {
                    children.append(.init(type: .listItem, content: blocks[index].content))
                    index += 1
                }
                grouped.append(.init(type: block.type, children: children))
            case .checklist:
                var children: [NotesSemanticDocument.Block] = []
                while index < blocks.count, blocks[index].type == .checklist {
                    children.append(
                        .init(
                            type: .listItem,
                            content: blocks[index].content,
                            checked: blocks[index].checked
                        )
                    )
                    index += 1
                }
                grouped.append(.init(type: .checklist, children: children))
            case .blockquote:
                var children: [NotesSemanticDocument.Block] = []
                while index < blocks.count, blocks[index].type == .blockquote {
                    children.append(.paragraph(blocks[index].content))
                    index += 1
                }
                grouped.append(.init(type: .blockquote, children: children))
            default:
                grouped.append(block)
                index += 1
            }
        }

        return grouped
    }

    static func presentationIntentBlockMarker(
        from run: AttributedString.Runs.Run
    ) -> String? {
        guard let intent = run.attributes[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] else {
            return nil
        }
        let kinds = intent.components.map(\.kind)
        if kinds.contains(.codeBlock(languageHint: nil))
            || kinds.contains(where: {
                if case .codeBlock = $0 { return true }
                return false
            }) {
            return NotesSemanticDocument.BlockType.codeBlock.rawValue
        }
        if kinds.contains(.blockQuote) {
            return NotesSemanticDocument.BlockType.blockquote.rawValue
        }
        if kinds.contains(.orderedList), kinds.contains(where: {
            if case .listItem = $0 { return true }
            return false
        }) {
            return NotesSemanticDocument.BlockType.orderedList.rawValue
        }
        if kinds.contains(.unorderedList), kinds.contains(where: {
            if case .listItem = $0 { return true }
            return false
        }) {
            return NotesSemanticDocument.BlockType.unorderedList.rawValue
        }
        return nil
    }

    static func decodeRunCharacters(
        _ characters: AttributedString.CharacterView,
        marks: [NotesSemanticDocument.InlineMark],
        link: NotesSemanticDocument.Link?,
        resolvedBlockType: NotesSemanticDocument.BlockType?,
        blocks: inout [NotesSemanticDocument.Block],
        currentSegments: inout [NotesSemanticDocument.InlineSegment],
        currentBlockMarker: inout String?,
        endedWithStructuralNewline: inout Bool
    ) {
        var buffer = ""

        for character in characters {
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
}

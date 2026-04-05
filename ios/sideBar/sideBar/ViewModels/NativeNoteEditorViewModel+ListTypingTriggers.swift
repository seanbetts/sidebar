@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    private struct ListTypingTrigger {
        let text: String
        let replacementBlocks: [NotesSemanticDocument.Block]
        let insertionBlockIndexOffset: Int
        let typingBlockType: NotesSemanticDocument.BlockType
    }

    private static let listTypingTriggers: [ListTypingTrigger] = [
        .init(
            text: "- ",
            replacementBlocks: [
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "", marks: [])])
                    ]
                )
            ],
            insertionBlockIndexOffset: 0,
            typingBlockType: .unorderedList
        ),
        .init(
            text: "* ",
            replacementBlocks: [
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "", marks: [])])
                    ]
                )
            ],
            insertionBlockIndexOffset: 0,
            typingBlockType: .unorderedList
        ),
        .init(
            text: "1. ",
            replacementBlocks: [
                .init(
                    type: .orderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "", marks: [])])
                    ]
                )
            ],
            insertionBlockIndexOffset: 0,
            typingBlockType: .orderedList
        ),
        .init(
            text: "[] ",
            replacementBlocks: [
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "", marks: [])], checked: false)
                    ]
                )
            ],
            insertionBlockIndexOffset: 0,
            typingBlockType: .checklist
        ),
        .init(
            text: "> ",
            replacementBlocks: [
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "", marks: [])])
                    ]
                )
            ],
            insertionBlockIndexOffset: 0,
            typingBlockType: .blockquote
        ),
        .init(
            text: "---",
            replacementBlocks: [
                .init(type: .divider),
                .paragraph([.init(text: "", marks: [])])
            ],
            insertionBlockIndexOffset: 1,
            typingBlockType: .paragraph
        )
    ]

    func listTypingTriggerMutation(
        in document: NotesSemanticDocument,
        selectionRange: Range<Int>,
        replacementText: String
    ) -> StructuralReplacementMutation? {
        guard selectionRange.isEmpty, replacementText == " " || replacementText == "-" else { return nil }
        guard let blockInfo = blockInfoContainingCharacterOffset(selectionRange.lowerBound, in: document) else {
            return nil
        }
        guard blockInfo.block.type == .paragraph else { return nil }

        let blockText = blockPlainText(blockInfo.block)
        let selectionOffset = selectionRange.lowerBound - blockInfo.range.lowerBound
        guard selectionOffset >= 0, selectionOffset <= blockText.count else { return nil }

        let insertionIndex = blockText.index(blockText.startIndex, offsetBy: selectionOffset)
        let updatedParagraphText = String(blockText[..<insertionIndex])
            + replacementText
            + String(blockText[insertionIndex...])
        guard let trigger = Self.listTypingTriggers.first(where: { $0.text == updatedParagraphText }) else {
            return nil
        }

        var updatedBlocks = document.blocks
        updatedBlocks.replaceSubrange(
            blockInfo.index...blockInfo.index,
            with: trigger.replacementBlocks
        )
        let updatedDocument = NotesSemanticDocument(version: document.version, blocks: updatedBlocks)
        let insertionBlockIndex = blockInfo.index + trigger.insertionBlockIndexOffset
        let insertionOffset = documentBlockInfos(in: updatedDocument)[insertionBlockIndex].range.lowerBound

        return StructuralReplacementMutation(
            document: updatedDocument,
            insertionOffset: insertionOffset,
            typingBlockType: trigger.typingBlockType
        )
    }
}

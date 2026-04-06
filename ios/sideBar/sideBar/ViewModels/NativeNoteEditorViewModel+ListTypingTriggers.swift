@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    private struct ListTypingTrigger {
        let text: String
        let replacementBlock: NotesSemanticDocument.Block
        let typingBlockType: NotesSemanticDocument.BlockType
    }

    private static let listTypingTriggers: [ListTypingTrigger] = [
        .init(
            text: "- ",
            replacementBlock: .init(
                type: .unorderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "", marks: [])])
                ]
            ),
            typingBlockType: .unorderedList
        ),
        .init(
            text: "* ",
            replacementBlock: .init(
                type: .unorderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "", marks: [])])
                ]
            ),
            typingBlockType: .unorderedList
        ),
        .init(
            text: "1. ",
            replacementBlock: .init(
                type: .orderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "", marks: [])])
                ]
            ),
            typingBlockType: .orderedList
        ),
        .init(
            text: "[] ",
            replacementBlock: .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "", marks: [])], checked: false)
                ]
            ),
            typingBlockType: .checklist
        ),
        .init(
            text: "> ",
            replacementBlock: .init(
                type: .blockquote,
                children: [
                    .paragraph([.init(text: "", marks: [])])
                ]
            ),
            typingBlockType: .blockquote
        )
    ]

    func listTypingTriggerMutation(
        in document: NotesSemanticDocument,
        selectionRange: Range<Int>,
        replacementText: String
    ) -> StructuralReplacementMutation? {
        guard replacementText == " ", selectionRange.isEmpty else { return nil }
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
        updatedBlocks[blockInfo.index] = trigger.replacementBlock
        let updatedDocument = NotesSemanticDocument(version: document.version, blocks: updatedBlocks)

        return StructuralReplacementMutation(
            document: updatedDocument,
            insertionOffset: blockInfo.range.lowerBound + blockPlainText(trigger.replacementBlock).count,
            typingBlockType: trigger.typingBlockType
        )
    }
}

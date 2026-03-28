@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    private struct ListTypingTrigger {
        let text: String
        let listType: NotesSemanticDocument.BlockType
    }

    private static let listTypingTriggers: [ListTypingTrigger] = [
        .init(text: "- ", listType: .unorderedList),
        .init(text: "* ", listType: .unorderedList),
        .init(text: "1. ", listType: .orderedList)
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

        let updatedBlock = NotesSemanticDocument.Block(
            type: trigger.listType,
            children: [
                .init(type: .listItem, content: [.init(text: "", marks: [])])
            ]
        )
        var updatedBlocks = document.blocks
        updatedBlocks[blockInfo.index] = updatedBlock

        return StructuralReplacementMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: blockInfo.range.lowerBound + blockPlainText(updatedBlock).count,
            typingBlockType: trigger.listType
        )
    }
}

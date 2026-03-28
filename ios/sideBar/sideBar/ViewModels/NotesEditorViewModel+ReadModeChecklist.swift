import Foundation

extension NotesEditorViewModel {
    func toggleChecklistItemInReadMode(
        blockIndex: Int,
        itemIndex: Int
    ) async {
        guard currentNoteId != nil else { return }

        let sourceDocument = currentSemanticDocumentSnapshot()
        guard blockIndex >= 0, blockIndex < sourceDocument.blocks.count else { return }

        var blocks = sourceDocument.blocks
        let block = blocks[blockIndex]
        guard block.type == .checklist,
              var children = block.children,
              itemIndex >= 0,
              itemIndex < children.count else {
            return
        }

        let currentItem = children[itemIndex]
        children[itemIndex] = NotesSemanticDocument.Block(
            type: .listItem,
            content: currentItem.content,
            checked: currentItem.checked != true
        )
        blocks[blockIndex] = NotesSemanticDocument.Block(
            type: .checklist,
            children: children
        )

        let updatedDocument = NotesSemanticDocument(
            version: sourceDocument.version,
            blocks: blocks
        )

        applyLocalReadModeSnapshot(updatedDocument)
        await saveDocumentSnapshotIfNeeded(updatedDocument, force: true)
    }
}

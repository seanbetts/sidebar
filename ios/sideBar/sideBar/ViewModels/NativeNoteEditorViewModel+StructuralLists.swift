@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    struct ListItemSelectionContext {
        let childIndex: Int
        let child: NotesSemanticDocument.Block
        let contentOffset: Int
    }

    func mutateListReturn(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionOffset: Int,
        blockText _: String
    ) -> StructuralReplacementMutation? {
        guard blockInfo.block.type == .unorderedList
                || blockInfo.block.type == .orderedList
                || blockInfo.block.type == .checklist else {
            return nil
        }

        var children = blockInfo.block.children ?? []
        guard let context = listItemSelectionContext(
            in: blockInfo.block,
            selectionOffset: selectionOffset
        ) else {
            return nil
        }

        if isEmptyListItem(context.child), context.contentOffset == 0 {
            return emptyListItemExitMutation(
                in: document,
                blockInfo: blockInfo,
                emptyItemIndex: context.childIndex
            )
        }

        let split = splitInlineSegments(context.child.content, at: context.contentOffset)
        children[context.childIndex] = .init(
            type: .listItem,
            content: normalizedInlineSegments(split.leading),
            checked: context.child.checked
        )
        children.insert(
            .init(
                type: .listItem,
                content: normalizedInlineSegments(split.trailing),
                checked: blockInfo.block.type == .checklist ? false : nil
            ),
            at: context.childIndex + 1
        )

        let updatedBlock = NotesSemanticDocument.Block(
            type: blockInfo.block.type,
            children: children
        )
        var updatedBlocks = document.blocks
        updatedBlocks[blockInfo.index] = updatedBlock

        return StructuralReplacementMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: blockInfo.range.lowerBound
                + listItemContentStartOffset(in: updatedBlock, itemIndex: context.childIndex + 1),
            typingBlockType: blockInfo.block.type
        )
    }

    func structuralDeleteBackwardMutation(
        in document: NotesSemanticDocument
    ) -> StructuralReplacementMutation? {
        guard case .insertionPoint = selection.indices(in: attributedContent) else { return nil }
        guard let blockInfo = blockInfoContainingSelectionStart(in: document) else { return nil }

        let blockText = blockPlainText(blockInfo.block)
        let selectionOffset = max(
            0,
            min(
                selectionStartCharacterOffset(in: attributedContent) - blockInfo.range.lowerBound,
                blockText.count
            )
        )

        switch blockInfo.block.type {
        case .unorderedList, .orderedList, .checklist:
            return mutateListDeleteBackward(
                in: document,
                blockInfo: blockInfo,
                selectionOffset: selectionOffset
            )
        case .blockquote:
            return mutateBlockquoteDeleteBackward(
                in: document,
                blockInfo: blockInfo,
                selectionOffset: selectionOffset
            )
        default:
            return nil
        }
    }

    func mutateListDeleteBackward(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionOffset: Int
    ) -> StructuralReplacementMutation? {
        guard let context = listItemSelectionContext(
            in: blockInfo.block,
            selectionOffset: selectionOffset
        ) else {
            return nil
        }
        guard isEmptyListItem(context.child), context.contentOffset == 0 else {
            return nil
        }

        return emptyListItemExitMutation(
            in: document,
            blockInfo: blockInfo,
            emptyItemIndex: context.childIndex
        )
    }

    func replaceTextInsideListContainer(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionRange: Range<Int>,
        replacementText: String
    ) -> StructuralReplacementMutation? {
        guard replacementText.contains("\n") else { return nil }
        guard blockInfo.block.type == .unorderedList
                || blockInfo.block.type == .orderedList
                || blockInfo.block.type == .checklist else {
            return nil
        }

        var children = blockInfo.block.children ?? []
        let selectionStartOffset = max(0, selectionRange.lowerBound - blockInfo.range.lowerBound)
        let selectionEndOffset = max(selectionStartOffset, selectionRange.upperBound - blockInfo.range.lowerBound)
        guard let startContext = listItemSelectionContext(
            in: blockInfo.block,
            selectionOffset: selectionStartOffset
        ),
            let endContext = listItemSelectionContext(
                in: blockInfo.block,
                selectionOffset: selectionEndOffset
            ),
            startContext.childIndex <= endContext.childIndex else {
            return nil
        }

        let insertedMarks = inlineMarksForStructuralInsertion().filter { mark in
            blockInfo.block.type != .checklist || mark != .strikethrough
        }
        let lines = replacementText.components(separatedBy: "\n")
        guard lines.count > 1 else { return nil }

        let leading = splitInlineSegments(
            startContext.child.content,
            at: startContext.contentOffset
        ).leading
        let trailing = splitInlineSegments(
            endContext.child.content,
            at: endContext.contentOffset
        ).trailing

        var replacementChildren: [NotesSemanticDocument.Block] = []
        for (lineIndex, line) in lines.enumerated() {
            var content: [NotesSemanticDocument.InlineSegment] = []
            if lineIndex == 0 {
                appendSegments(leading, to: &content)
            }
            appendSegmentText(line, marks: insertedMarks, to: &content)
            if lineIndex == lines.index(before: lines.endIndex) {
                appendSegments(trailing, to: &content)
            }

            let checked: Bool?
            if blockInfo.block.type == .checklist {
                checked = lineIndex == 0 ? (startContext.child.checked ?? false) : false
            } else {
                checked = nil
            }
            replacementChildren.append(
                .init(
                    type: .listItem,
                    content: normalizedInlineSegments(content),
                    checked: checked
                )
            )
        }

        children.replaceSubrange(
            startContext.childIndex...endContext.childIndex,
            with: replacementChildren
        )
        let updatedBlock = NotesSemanticDocument.Block(
            type: blockInfo.block.type,
            children: children
        )
        var updatedBlocks = document.blocks
        updatedBlocks[blockInfo.index] = updatedBlock

        let insertedLastChildIndex = startContext.childIndex + replacementChildren.count - 1
        let insertionOffset = blockInfo.range.lowerBound
            + listItemContentStartOffset(in: updatedBlock, itemIndex: insertedLastChildIndex)
            + (lines.last ?? "").count
        return StructuralReplacementMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: insertionOffset,
            typingBlockType: blockInfo.block.type
        )
    }

    func listItemSelectionContext(
        in block: NotesSemanticDocument.Block,
        selectionOffset: Int
    ) -> ListItemSelectionContext? {
        let children = block.children ?? []
        guard children.isEmpty == false else { return nil }

        var runningOffset = 0
        for (itemIndex, child) in children.enumerated() {
            if itemIndex > 0 {
                runningOffset += 1
            }

            let prefixLength = listItemPrefixLength(for: block.type, itemIndex: itemIndex)
            let textStart = runningOffset + prefixLength
            let textLength = inlineTextLength(child.content)
            let itemEnd = textStart + textLength

            if selectionOffset <= textStart {
                return ListItemSelectionContext(
                    childIndex: itemIndex,
                    child: child,
                    contentOffset: 0
                )
            }
            if selectionOffset <= itemEnd {
                return ListItemSelectionContext(
                    childIndex: itemIndex,
                    child: child,
                    contentOffset: selectionOffset - textStart
                )
            }

            runningOffset = itemEnd
        }

        return nil
    }

    func listItemContentStartOffset(
        in block: NotesSemanticDocument.Block,
        itemIndex: Int
    ) -> Int {
        let children = block.children ?? []
        var runningOffset = 0

        for (currentIndex, child) in children.enumerated() {
            if currentIndex > 0 {
                runningOffset += 1
            }

            let prefixLength = listItemPrefixLength(for: block.type, itemIndex: currentIndex)
            if currentIndex == itemIndex {
                return runningOffset + prefixLength
            }
            runningOffset += prefixLength + inlineTextLength(child.content)
        }

        return runningOffset
    }

    func listItemPrefixLength(
        for blockType: NotesSemanticDocument.BlockType,
        itemIndex: Int
    ) -> Int {
        switch blockType {
        case .unorderedList:
            return "- ".count
        case .orderedList:
            return "\(itemIndex + 1). ".count
        case .checklist:
            return "- [ ] ".count
        default:
            return 0
        }
    }

    func emptyListItemExitMutation(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        emptyItemIndex: Int
    ) -> StructuralReplacementMutation? {
        let children = blockInfo.block.children ?? []
        guard children.indices.contains(emptyItemIndex),
              isEmptyListItem(children[emptyItemIndex]) else {
            return nil
        }

        let leadingChildren = Array(children[..<emptyItemIndex])
        let trailingChildren = emptyItemIndex + 1 < children.count
            ? Array(children[(emptyItemIndex + 1)...])
            : []
        var updatedBlocks = Array(document.blocks[..<blockInfo.index])

        if leadingChildren.isEmpty == false {
            updatedBlocks.append(
                NotesSemanticDocument.Block(
                    type: blockInfo.block.type,
                    children: leadingChildren
                )
            )
        }

        let paragraphIndex = updatedBlocks.count
        updatedBlocks.append(.paragraph([.init(text: "", marks: [])]))

        if trailingChildren.isEmpty == false {
            updatedBlocks.append(
                NotesSemanticDocument.Block(
                    type: blockInfo.block.type,
                    children: trailingChildren
                )
            )
        }

        if blockInfo.index + 1 < document.blocks.count {
            updatedBlocks.append(contentsOf: document.blocks[(blockInfo.index + 1)...])
        }

        let updatedDocument = NotesSemanticDocument(
            version: document.version,
            blocks: updatedBlocks
        )
        let paragraphStartOffset = documentBlockInfos(in: updatedDocument)[paragraphIndex].range.lowerBound

        return StructuralReplacementMutation(
            document: updatedDocument,
            insertionOffset: paragraphStartOffset,
            typingBlockType: .paragraph
        )
    }

    func isEmptyListItem(_ block: NotesSemanticDocument.Block) -> Bool {
        guard block.type == .listItem else { return false }
        return block.content.allSatisfy { $0.text.isEmpty }
    }
}

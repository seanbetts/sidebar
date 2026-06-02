@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    struct BlockquoteSelectionContext {
        let childIndex: Int
        let child: NotesSemanticDocument.Block
        let contentOffset: Int
    }

    func mutateBlockquoteReturn(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionOffset: Int
    ) -> StructuralReplacementMutation? {
        guard blockInfo.block.type == .blockquote else { return nil }

        var children = blockInfo.block.children ?? []
        guard let context = blockquoteSelectionContext(
            in: blockInfo.block,
            selectionOffset: selectionOffset
        ) else {
            return nil
        }

        if isEmptyBlockquoteParagraph(context.child), context.contentOffset == 0 {
            return emptyBlockquoteParagraphExitMutation(
                in: document,
                blockInfo: blockInfo,
                emptyParagraphIndex: context.childIndex
            )
        }

        let split = splitInlineSegments(context.child.content, at: context.contentOffset)
        children[context.childIndex] = .paragraph(normalizedInlineSegments(split.leading))
        children.insert(
            .paragraph(normalizedInlineSegments(split.trailing)),
            at: context.childIndex + 1
        )

        let updatedBlock = NotesSemanticDocument.Block(
            type: .blockquote,
            children: children
        )
        var updatedBlocks = document.blocks
        updatedBlocks[blockInfo.index] = updatedBlock

        return StructuralReplacementMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: blockInfo.range.lowerBound
                + blockquoteChildContentStartOffset(in: updatedBlock, childIndex: context.childIndex + 1),
            typingBlockType: .blockquote
        )
    }

    func mutateBlockquoteDeleteBackward(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionOffset: Int
    ) -> StructuralReplacementMutation? {
        guard let context = blockquoteSelectionContext(
            in: blockInfo.block,
            selectionOffset: selectionOffset
        ) else {
            return nil
        }
        guard isEmptyBlockquoteParagraph(context.child), context.contentOffset == 0 else {
            return nil
        }

        return emptyBlockquoteParagraphExitMutation(
            in: document,
            blockInfo: blockInfo,
            emptyParagraphIndex: context.childIndex
        )
    }

    func replaceTextInsideBlockquote(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        selectionRange: Range<Int>,
        replacementText: String
    ) -> StructuralReplacementMutation? {
        guard replacementText.contains("\n"), blockInfo.block.type == .blockquote else { return nil }

        var children = blockInfo.block.children ?? []
        let selectionStartOffset = max(0, selectionRange.lowerBound - blockInfo.range.lowerBound)
        let selectionEndOffset = max(selectionStartOffset, selectionRange.upperBound - blockInfo.range.lowerBound)
        guard let startContext = blockquoteSelectionContext(
            in: blockInfo.block,
            selectionOffset: selectionStartOffset
        ),
            let endContext = blockquoteSelectionContext(
                in: blockInfo.block,
                selectionOffset: selectionEndOffset
            ),
            startContext.childIndex <= endContext.childIndex else {
            return nil
        }

        let insertedMarks = inlineMarksForStructuralInsertion()
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
            replacementChildren.append(.paragraph(normalizedInlineSegments(content)))
        }

        children.replaceSubrange(
            startContext.childIndex...endContext.childIndex,
            with: replacementChildren
        )
        let updatedBlock = NotesSemanticDocument.Block(
            type: .blockquote,
            children: children
        )
        var updatedBlocks = document.blocks
        updatedBlocks[blockInfo.index] = updatedBlock

        let insertedLastChildIndex = startContext.childIndex + replacementChildren.count - 1
        let insertionOffset = blockInfo.range.lowerBound
            + blockquoteChildContentStartOffset(in: updatedBlock, childIndex: insertedLastChildIndex)
            + (lines.last ?? "").count
        return StructuralReplacementMutation(
            document: NotesSemanticDocument(version: document.version, blocks: updatedBlocks),
            insertionOffset: insertionOffset,
            typingBlockType: .blockquote
        )
    }

    func blockquoteSelectionContext(
        in block: NotesSemanticDocument.Block,
        selectionOffset: Int
    ) -> BlockquoteSelectionContext? {
        let children = block.children ?? []
        guard children.isEmpty == false else { return nil }

        var runningOffset = 0
        for (childIndex, child) in children.enumerated() {
            if childIndex > 0 {
                runningOffset += 1
            }

            let prefixLength = "> ".count
            let textStart = runningOffset + prefixLength
            let textLength = inlineTextLength(child.content)
            let childEnd = textStart + textLength

            if selectionOffset <= textStart {
                return BlockquoteSelectionContext(
                    childIndex: childIndex,
                    child: child,
                    contentOffset: 0
                )
            }
            if selectionOffset <= childEnd {
                return BlockquoteSelectionContext(
                    childIndex: childIndex,
                    child: child,
                    contentOffset: selectionOffset - textStart
                )
            }

            runningOffset = childEnd
        }

        return nil
    }

    func blockquoteChildContentStartOffset(
        in block: NotesSemanticDocument.Block,
        childIndex: Int
    ) -> Int {
        let children = block.children ?? []
        var runningOffset = 0

        for (currentIndex, child) in children.enumerated() {
            if currentIndex > 0 {
                runningOffset += 1
            }

            let prefixLength = "> ".count
            if currentIndex == childIndex {
                return runningOffset + prefixLength
            }
            runningOffset += prefixLength + inlineTextLength(child.content)
        }

        return runningOffset
    }

    func emptyBlockquoteParagraphExitMutation(
        in document: NotesSemanticDocument,
        blockInfo: DocumentBlockInfo,
        emptyParagraphIndex: Int
    ) -> StructuralReplacementMutation? {
        let children = blockInfo.block.children ?? []
        guard children.indices.contains(emptyParagraphIndex),
              isEmptyBlockquoteParagraph(children[emptyParagraphIndex]) else {
            return nil
        }

        let leadingChildren = Array(children[..<emptyParagraphIndex])
        let trailingChildren = emptyParagraphIndex + 1 < children.count
            ? Array(children[(emptyParagraphIndex + 1)...])
            : []
        var updatedBlocks = Array(document.blocks[..<blockInfo.index])

        if leadingChildren.isEmpty == false {
            updatedBlocks.append(
                NotesSemanticDocument.Block(
                    type: .blockquote,
                    children: leadingChildren
                )
            )
        }

        let paragraphIndex = updatedBlocks.count
        updatedBlocks.append(.paragraph([.init(text: "", marks: [])]))

        if trailingChildren.isEmpty == false {
            updatedBlocks.append(
                NotesSemanticDocument.Block(
                    type: .blockquote,
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

    func isEmptyBlockquoteParagraph(_ block: NotesSemanticDocument.Block) -> Bool {
        guard block.type == .paragraph else { return false }
        return block.content.allSatisfy { $0.text.isEmpty }
    }
}

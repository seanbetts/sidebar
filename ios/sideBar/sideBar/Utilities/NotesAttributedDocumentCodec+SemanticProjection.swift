import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension NotesAttributedDocumentCodec {
    static func attributedBlocks(
        from blocks: [NotesSemanticDocument.Block],
        baseFontSize: CGFloat,
        identitySource: inout NotesPresentationIntentIdentitySource
    ) -> AttributedString {
        guard let firstBlock = blocks.first else {
            return AttributedString()
        }

        var attributed = renderedTopLevelBlock(
            firstBlock,
            previousBlockType: nil,
            nextBlockType: blocks.dropFirst().first?.type,
            baseFontSize: baseFontSize,
            identitySource: &identitySource
        )

        var previousBlock = firstBlock

        for (offset, block) in blocks.dropFirst().enumerated() {
            attributed.append(
                attributedBoundary(
                    after: previousBlock.type,
                    before: block.type,
                    baseFontSize: baseFontSize
                )
            )
            attributed.append(
                renderedTopLevelBlock(
                    block,
                    previousBlockType: previousBlock.type,
                    nextBlockType: (offset + 2) < blocks.count ? blocks[offset + 2].type : nil,
                    baseFontSize: baseFontSize,
                    identitySource: &identitySource
                )
            )
            previousBlock = block
        }

        return attributed
    }

    static func legacyAttributedBlocks(
        from blocks: [NotesSemanticDocument.Block],
        baseFontSize: CGFloat
    ) -> AttributedString {
        var attributed = AttributedString()
        var orderedListIndex = 0

        var previousBlockType: NotesSemanticDocument.BlockType?

        for (index, block) in blocks.enumerated() {
            let nextBlockType = index < blocks.index(before: blocks.endIndex)
                ? blocks[index + 1].type
                : nil
            if index > 0 {
                attributed.append(
                    attributedBoundary(
                        after: previousBlockType,
                        before: block.type,
                        baseFontSize: baseFontSize
                    )
                )
            }

            if block.type == .orderedList {
                attributed.append(
                    legacyAttributedBlock(
                        from: block,
                        baseFontSize: baseFontSize,
                        orderedListIndex: orderedListIndex,
                        previousBlockType: previousBlockType,
                        nextBlockType: nextBlockType
                    )
                )
                orderedListIndex += 1
            } else {
                attributed.append(
                    legacyAttributedBlock(
                        from: block,
                        baseFontSize: baseFontSize,
                        orderedListIndex: 0,
                        previousBlockType: previousBlockType,
                        nextBlockType: nextBlockType
                    )
                )
                orderedListIndex = 0
            }
            previousBlockType = block.type
        }

        return attributed
    }

    static func usesPresentationIntentProjection(
        blocks: [NotesSemanticDocument.Block]
    ) -> Bool {
        blocks.contains { block in
            switch block.type {
            case .codeBlock, .orderedList, .unorderedList, .checklist, .blockquote:
                return true
            default:
                return usesPresentationIntentProjection(blocks: block.children ?? [])
            }
        }
    }

    private static func renderedTopLevelBlock(
        _ sourceBlock: NotesSemanticDocument.Block,
        previousBlockType: NotesSemanticDocument.BlockType?,
        nextBlockType: NotesSemanticDocument.BlockType?,
        baseFontSize: CGFloat,
        identitySource: inout NotesPresentationIntentIdentitySource
    ) -> AttributedString {
        let block = renderingCopy(of: sourceBlock)
        let spacingBefore = additionalSpacingBefore(
            for: block.type,
            previousBlockType: previousBlockType,
            baseFontSize: baseFontSize
        )
        let spacingAfter = additionalSpacingAfter(
            for: block.type,
            nextBlockType: nextBlockType,
            baseFontSize: baseFontSize
        )
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .listItem:
            return attributedParagraph(
                from: block.content,
                blockType: block.type,
                baseFontSize: baseFontSize,
                additionalSpacingBefore: spacingBefore,
                additionalSpacingAfter: spacingAfter
            )
        case .codeBlock:
            return styledPresentationIntentText(
                block.content.map(\.text).joined(),
                blockType: .codeBlock,
                baseFontSize: baseFontSize,
                additionalSpacingBefore: spacingBefore,
                additionalSpacingAfter: spacingAfter,
                presentationIntent: PresentationIntent(
                    .codeBlock(languageHint: nil),
                    identity: identitySource.makeIdentity(),
                    parent: nil
                )
            )
        case .orderedList, .unorderedList, .checklist:
            return attributedListContainer(
                from: block,
                nextBlockType: nextBlockType,
                baseFontSize: baseFontSize,
                identitySource: &identitySource,
                semanticParent: nil
            )
        case .blockquote:
            return attributedBlockquote(
                from: block,
                baseFontSize: baseFontSize,
                identitySource: &identitySource,
                semanticParent: nil
            )
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            assertionFailure(
                "Unsupported block type should have been handled before rendering: \(block.type.rawValue)"
            )
            return AttributedString("")
        }
    }

    static func attributedBlock(
        from block: NotesSemanticDocument.Block,
        baseFontSize: CGFloat,
        identitySource: inout NotesPresentationIntentIdentitySource,
        semanticParent: PresentationIntent?
    ) -> AttributedString {
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .listItem:
            return attributedParagraph(
                from: block.content,
                blockType: block.type,
                baseFontSize: baseFontSize
            )
        case .codeBlock:
            return styledPresentationIntentText(
                block.content.map(\.text).joined(),
                blockType: .codeBlock,
                baseFontSize: baseFontSize,
                presentationIntent: PresentationIntent(
                    .codeBlock(languageHint: nil),
                    identity: identitySource.makeIdentity(),
                    parent: semanticParent
                )
            )
        case .orderedList, .unorderedList, .checklist:
            return attributedListContainer(
                from: block,
                nextBlockType: nil,
                baseFontSize: baseFontSize,
                identitySource: &identitySource,
                semanticParent: semanticParent
            )
        case .blockquote:
            return attributedBlockquote(
                from: block,
                baseFontSize: baseFontSize,
                identitySource: &identitySource,
                semanticParent: semanticParent
            )
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            assertionFailure(
                "Unsupported block type should have been handled before rendering: \(block.type.rawValue)"
            )
            return AttributedString("")
        }
    }

    private static func legacyAttributedBlock(
        from block: NotesSemanticDocument.Block,
        baseFontSize: CGFloat,
        orderedListIndex: Int,
        previousBlockType: NotesSemanticDocument.BlockType?,
        nextBlockType: NotesSemanticDocument.BlockType?
    ) -> AttributedString {
        let spacingBefore = additionalSpacingBefore(
            for: block.type,
            previousBlockType: previousBlockType,
            baseFontSize: baseFontSize
        )
        let spacingAfter = additionalSpacingAfter(
            for: block.type,
            nextBlockType: nextBlockType,
            baseFontSize: baseFontSize
        )
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .listItem, .codeBlock:
            return attributedParagraph(
                from: block.content,
                blockType: block.type,
                baseFontSize: baseFontSize,
                additionalSpacingBefore: spacingBefore,
                additionalSpacingAfter: spacingAfter
            )
        case .unorderedList, .orderedList, .checklist, .blockquote:
            let usesListRunContext = isListBlockType(block.type)
            return attributedParagraph(
                from: block.content,
                blockType: block.type,
                baseFontSize: baseFontSize,
                previousBlockType: listRunContextBlockType(block.type, value: previousBlockType),
                nextBlockType: listRunContextBlockType(block.type, value: nextBlockType),
                additionalSpacingBefore: usesListRunContext ? 0 : spacingBefore,
                additionalSpacingAfter: usesListRunContext ? 0 : spacingAfter,
                visiblePrefix: legacyVisiblePrefix(
                    for: block,
                    orderedListIndex: orderedListIndex
                )
            )
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            assertionFailure(
                "Unsupported block type should have been handled before rendering: \(block.type.rawValue)"
            )
            return AttributedString("")
        }
    }

    private static func attributedListContainer(
        from block: NotesSemanticDocument.Block,
        nextBlockType: NotesSemanticDocument.BlockType?,
        baseFontSize: CGFloat,
        identitySource: inout NotesPresentationIntentIdentitySource,
        semanticParent: PresentationIntent?
    ) -> AttributedString {
        let containerKind: PresentationIntent.Kind = switch block.type {
        case .orderedList:
            .orderedList
        case .unorderedList, .checklist:
            .unorderedList
        default:
            .unorderedList
        }
        let containerIntent = PresentationIntent(
            containerKind,
            identity: identitySource.makeIdentity(),
            parent: semanticParent
        )
        let children = block.children ?? []
        var attributed = AttributedString()

        for (index, child) in children.enumerated() {
            if index > 0 {
                attributed.append(
                    attributedBoundary(for: block.type, baseFontSize: baseFontSize)
                )
            }
            let itemPreviousBlockType: NotesSemanticDocument.BlockType? = index > 0 ? block.type : nil
            let itemNextBlockType: NotesSemanticDocument.BlockType? =
                index + 1 < children.count ? block.type : nextBlockType
            let itemIntent = PresentationIntent(
                .listItem(ordinal: index + 1),
                identity: identitySource.makeIdentity(),
                parent: containerIntent
            )
            let paragraphIntent = PresentationIntent(
                .paragraph,
                identity: identitySource.makeIdentity(),
                parent: itemIntent
            )
            let prefix = switch block.type {
            case .orderedList:
                "\(index + 1).\t"
            case .unorderedList:
                "\u{2022} "
            case .checklist:
                "- [\(child.checked == true ? "x" : " ")] "
            default:
                ""
            }
            attributed.append(
                attributedSemanticParagraph(
                    from: child.content,
                    blockType: block.type,
                    baseFontSize: baseFontSize,
                    previousBlockType: itemPreviousBlockType,
                    nextBlockType: itemNextBlockType,
                    visiblePrefix: prefix,
                    checklistItemChecked: block.type == .checklist && child.checked == true,
                    presentationIntent: paragraphIntent
                )
            )
        }
        return attributed
    }

    private static func attributedBlockquote(
        from block: NotesSemanticDocument.Block,
        baseFontSize: CGFloat,
        identitySource: inout NotesPresentationIntentIdentitySource,
        semanticParent: PresentationIntent?
    ) -> AttributedString {
        let quoteIntent = PresentationIntent(
            .blockQuote,
            identity: identitySource.makeIdentity(),
            parent: semanticParent
        )
        let children = block.children ?? []
        var attributed = AttributedString()

        for (index, child) in children.enumerated() {
            if index > 0 {
                attributed.append(
                    attributedBoundary(for: .blockquote, baseFontSize: baseFontSize)
                )
            }
            let paragraphIntent = PresentationIntent(
                .paragraph,
                identity: identitySource.makeIdentity(),
                parent: quoteIntent
            )
            attributed.append(
                attributedSemanticParagraph(
                    from: child.content,
                    blockType: .blockquote,
                    baseFontSize: baseFontSize,
                    visiblePrefix: "> ",
                    presentationIntent: paragraphIntent
                )
            )
        }

        return attributed
    }

    private static func legacyVisiblePrefix(
        for block: NotesSemanticDocument.Block,
        orderedListIndex: Int
    ) -> String? {
        switch block.type {
        case .unorderedList:
            return "\u{2022} "
        case .orderedList:
            return "\(orderedListIndex + 1).\t"
        case .checklist:
            return "- [\(block.checked == true ? "x" : " ")] "
        case .blockquote:
            return "> "
        default:
            return nil
        }
    }

    private static func listRunContextBlockType(
        _ blockType: NotesSemanticDocument.BlockType,
        value: NotesSemanticDocument.BlockType?
    ) -> NotesSemanticDocument.BlockType? {
        guard isListBlockType(blockType) else { return nil }
        return value
    }

    private static func isListBlockType(_ blockType: NotesSemanticDocument.BlockType) -> Bool {
        switch blockType {
        case .unorderedList, .orderedList, .checklist:
            return true
        case .title,
             .paragraph,
             .heading,
             .subheading,
             .listItem,
             .blockquote,
             .codeBlock,
             .table,
             .tableRow,
             .tableCell,
             .media,
             .caption,
             .htmlBlock:
            return false
        }
    }

    private static func renderingCopy(
        of block: NotesSemanticDocument.Block
    ) -> NotesSemanticDocument.Block {
        NotesSemanticDocument.Block(
            type: block.type,
            content: block.content.map { segment in
                NotesSemanticDocument.InlineSegment(
                    text: String(segment.text),
                    marks: Array(segment.marks),
                    link: segment.link.map { .init(url: String($0.url)) }
                )
            },
            checked: block.checked,
            children: block.children?.map { child in
                renderingCopy(of: child)
            }
        )
    }

    private static func additionalSpacingBefore(
        for blockType: NotesSemanticDocument.BlockType,
        previousBlockType: NotesSemanticDocument.BlockType?,
        baseFontSize: CGFloat
    ) -> CGFloat {
        guard blockType != .codeBlock, previousBlockType == .codeBlock else { return 0 }
        return NoteTextParagraphMetrics.codeBlockPaddingAfter(baseFontSize: baseFontSize)
    }

    private static func additionalSpacingAfter(
        for blockType: NotesSemanticDocument.BlockType,
        nextBlockType: NotesSemanticDocument.BlockType?,
        baseFontSize: CGFloat
    ) -> CGFloat {
        guard blockType != .codeBlock, nextBlockType == .codeBlock else { return 0 }
        return NoteTextParagraphMetrics.codeBlockPaddingBefore(baseFontSize: baseFontSize)
    }
}

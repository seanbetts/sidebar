import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension NotesAttributedDocumentCodec {
    static func attributedBlocks(
        from blocks: [NotesSemanticDocument.Block],
        baseFontSize: CGFloat,
        identitySource: NotesPresentationIntentIdentitySource
    ) -> AttributedString {
        guard let firstBlock = blocks.first else {
            return AttributedString()
        }

        var attributed = renderedTopLevelBlock(
            firstBlock,
            baseFontSize: baseFontSize,
            identitySource: identitySource
        )

        for block in blocks.dropFirst() {
            attributed.append(
                attributedBoundary(
                    for: block.type,
                    baseFontSize: baseFontSize
                )
            )
            attributed.append(
                renderedTopLevelBlock(
                    block,
                    baseFontSize: baseFontSize,
                    identitySource: identitySource
                )
            )
        }

        return attributed
    }

    static func legacyAttributedBlocks(
        from blocks: [NotesSemanticDocument.Block],
        baseFontSize: CGFloat
    ) -> AttributedString {
        var attributed = AttributedString()
        var orderedListIndex = 0

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                attributed.append(
                    attributedBoundary(
                        for: block.type,
                        baseFontSize: baseFontSize
                    )
                )
            }

            if block.type == .orderedList {
                attributed.append(
                    legacyAttributedBlock(
                        from: block,
                        baseFontSize: baseFontSize,
                        orderedListIndex: orderedListIndex
                    )
                )
                orderedListIndex += 1
            } else {
                attributed.append(
                    legacyAttributedBlock(
                        from: block,
                        baseFontSize: baseFontSize,
                        orderedListIndex: 0
                    )
                )
                orderedListIndex = 0
            }
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
        baseFontSize: CGFloat,
        identitySource: NotesPresentationIntentIdentitySource
    ) -> AttributedString {
        let block = renderingCopy(of: sourceBlock)
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .listItem:
            return attributedParagraph(
                from: block.content,
                blockType: block.type,
                baseFontSize: baseFontSize
            )
        case .codeBlock:
            return bridgedFoundationPresentationIntentText(
                block.content.map(\.text).joined(),
                presentationIntent: PresentationIntent(
                    .codeBlock(languageHint: nil),
                    identity: identitySource.makeIdentity(),
                    parent: nil
                )
            )
        case .orderedList, .unorderedList, .checklist:
            return attributedListContainer(
                from: block,
                baseFontSize: baseFontSize,
                identitySource: identitySource,
                semanticParent: nil
            )
        case .blockquote:
            return attributedBlockquote(
                from: block,
                baseFontSize: baseFontSize,
                identitySource: identitySource,
                semanticParent: nil
            )
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            assertionFailure(
                "Unsupported block type should have been handled before rendering: \(block.type.rawValue)"
            )
            return AttributedString("")
        }
    }

    private static func attributedBlock(
        from block: NotesSemanticDocument.Block,
        baseFontSize: CGFloat,
        identitySource: NotesPresentationIntentIdentitySource,
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
            return bridgedFoundationPresentationIntentText(
                block.content.map(\.text).joined(),
                presentationIntent: PresentationIntent(
                    .codeBlock(languageHint: nil),
                    identity: identitySource.makeIdentity(),
                    parent: semanticParent
                )
            )
        case .orderedList, .unorderedList, .checklist:
            return attributedListContainer(
                from: block,
                baseFontSize: baseFontSize,
                identitySource: identitySource,
                semanticParent: semanticParent
            )
        case .blockquote:
            return attributedBlockquote(
                from: block,
                baseFontSize: baseFontSize,
                identitySource: identitySource,
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
        orderedListIndex: Int
    ) -> AttributedString {
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .listItem, .codeBlock:
            return attributedParagraph(
                from: block.content,
                blockType: block.type,
                baseFontSize: baseFontSize
            )
        case .unorderedList, .orderedList, .checklist, .blockquote:
            return attributedParagraph(
                from: block.content,
                blockType: block.type,
                baseFontSize: baseFontSize,
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
        baseFontSize: CGFloat,
        identitySource: NotesPresentationIntentIdentitySource,
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
                "\(index + 1). "
            case .unorderedList:
                "- "
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
                    visiblePrefix: prefix,
                    presentationIntent: paragraphIntent
                )
            )
        }
        return attributed
    }

    private static func attributedBlockquote(
        from block: NotesSemanticDocument.Block,
        baseFontSize: CGFloat,
        identitySource: NotesPresentationIntentIdentitySource,
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
            return "- "
        case .orderedList:
            return "\(orderedListIndex + 1). "
        case .checklist:
            return "- [\(block.checked == true ? "x" : " ")] "
        case .blockquote:
            return "> "
        default:
            return nil
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
            children: block.children?.map(renderingCopy)
        )
    }
}

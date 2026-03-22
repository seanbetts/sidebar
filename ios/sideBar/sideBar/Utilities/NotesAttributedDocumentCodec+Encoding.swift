import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
private final class NotesPresentationIntentIdentitySource {
    private var nextIdentity = 1

    func make(
        _ kind: PresentationIntent.Kind,
        parent: PresentationIntent? = nil
    ) -> PresentationIntent {
        let identity = nextIdentity
        nextIdentity += 1
        return PresentationIntent(kind, identity: identity, parent: parent)
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension NotesAttributedDocumentCodec {
    static func attributedString(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> AttributedString {
        if let unsupportedContent = NotesUnsupportedContent.detect(in: document) {
            unsupportedContent.reportDetected(
                context: "NotesAttributedDocumentCodec.attributedString"
            )
            return AttributedString("")
        }

        let attributed: AttributedString
        if usesPresentationIntentProjection(blocks: document.blocks) {
            let identitySource = NotesPresentationIntentIdentitySource()
            attributed = attributedBlocks(
                from: document.blocks,
                baseFontSize: baseFontSize,
                identitySource: identitySource
            )
        } else {
            attributed = legacyAttributedBlocks(
                from: document.blocks,
                baseFontSize: baseFontSize
            )
        }

        if attributed.characters.isEmpty {
            return AttributedString("")
        }

        return attributed
    }

    static func readAttributedString(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> AttributedString {
        let attributed = attributedString(from: document, baseFontSize: baseFontSize)
        return applyingDetectedLinks(to: attributed)
    }

    private static func attributedBoundary(
        for blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat
    ) -> AttributedString {
        var boundary = AttributedString("\n")
        let range = boundary.startIndex..<boundary.endIndex
        boundary[range].font = blockFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: false,
            italic: false
        )
        #if os(iOS)
        boundary[range][AttributeScopes.UIKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: blockType,
                bold: false,
                italic: false
            )
        #elseif os(macOS)
        boundary[range][AttributeScopes.AppKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: blockType,
                bold: false,
                italic: false
            )
        #endif
        boundary[range].paragraphStyle = paragraphStyle(
            for: blockType,
            baseFontSize: baseFontSize
        )
        boundary[range].noteBlock = blockMarker(for: blockType)
        boundary[range].noteStructuralBoundary = true
        return boundary
    }

    private static func attributedParagraph(
        from segments: [NotesSemanticDocument.InlineSegment],
        blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        visiblePrefix: String? = nil
    ) -> AttributedString {
        var paragraph = AttributedString()

        if let visiblePrefix {
            var prefix = AttributedString(visiblePrefix)
            if !prefix.characters.isEmpty {
                let range = prefix.startIndex..<prefix.endIndex
                prefix[range].font = blockFont(
                    baseFontSize: baseFontSize,
                    blockType: blockType,
                    bold: false,
                    italic: false
                )
                prefix[range].paragraphStyle = paragraphStyle(
                    for: blockType,
                    baseFontSize: baseFontSize
                )
                if let blockMarker = blockMarker(for: blockType) {
                    prefix[range].noteBlock = blockMarker
                }
            }
            paragraph.append(prefix)
        }

        for segment in segments {
            var piece = AttributedString(segment.text)
            if !piece.characters.isEmpty {
                let range = piece.startIndex..<piece.endIndex
                let marks = Set(segment.marks)
                let inlineCode = marks.contains(.inlineCode)
                piece[range].font = blockFont(
                    baseFontSize: baseFontSize,
                    blockType: blockType,
                    bold: marks.contains(.bold),
                    italic: marks.contains(.italic),
                    inlineCode: inlineCode
                )
                #if os(iOS)
                piece[range][AttributeScopes.UIKitAttributes.FontAttribute.self] =
                    noteEditorPlatformFont(
                        baseFontSize: baseFontSize,
                        blockType: blockType,
                        bold: marks.contains(.bold),
                        italic: marks.contains(.italic),
                        inlineCode: inlineCode
                    )
                piece[range][AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] =
                    NoteTextAppearance.backgroundColor(
                        for: blockType,
                        inlineCode: inlineCode
                    )
                #elseif os(macOS)
                piece[range][AttributeScopes.AppKitAttributes.FontAttribute.self] =
                    noteEditorPlatformFont(
                        baseFontSize: baseFontSize,
                        blockType: blockType,
                        bold: marks.contains(.bold),
                        italic: marks.contains(.italic),
                        inlineCode: inlineCode
                    )
                piece[range][AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] =
                    NoteTextAppearance.backgroundColor(
                        for: blockType,
                        inlineCode: inlineCode
                    )
                #endif
                piece[range].underlineStyle = marks.contains(.underline) ? .single : nil
                piece[range].strikethroughStyle =
                    marks.contains(.strikethrough) ? .single : nil
                piece[range].link = segment.link.flatMap { URL(string: $0.url) }
                piece[range].paragraphStyle = paragraphStyle(
                    for: blockType,
                    baseFontSize: baseFontSize
                )
                if let blockMarker = blockMarker(for: blockType) {
                    piece[range].noteBlock = blockMarker
                }
            }
            paragraph.append(piece)
        }

        return paragraph
    }

    private static func attributedSemanticParagraph(
        from segments: [NotesSemanticDocument.InlineSegment],
        blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        visiblePrefix: String? = nil,
        presentationIntent: PresentationIntent
    ) -> AttributedString {
        let plainText = (visiblePrefix ?? "") + segments.map(\.text).joined()
        guard !plainText.isEmpty else { return AttributedString("") }
        let bridged = NSMutableAttributedString(string: plainText)
        bridged.addAttribute(
            NSAttributedString.Key("NSPresentationIntent"),
            value: presentationIntent,
            range: NSRange(location: 0, length: bridged.length)
        )
        return (try? AttributedString(bridged, including: \.foundation))
            ?? AttributedString(plainText)
    }

    private static func attributedBlocks(
        from blocks: [NotesSemanticDocument.Block],
        baseFontSize: CGFloat,
        identitySource: NotesPresentationIntentIdentitySource
    ) -> AttributedString {
        var attributed = AttributedString()

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                attributed.append(
                    attributedBoundary(
                        for: block.type,
                        baseFontSize: baseFontSize
                    )
                )
            }

            let blockAttributed = attributedBlock(
                from: block,
                baseFontSize: baseFontSize,
                identitySource: identitySource,
                semanticParent: nil
            )
            if attributed.characters.isEmpty {
                attributed = blockAttributed
            } else {
                attributed.append(blockAttributed)
            }
        }

        return attributed
    }

    private static func legacyAttributedBlocks(
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

            attributed.append(
                legacyAttributedBlock(
                    from: block,
                    baseFontSize: baseFontSize,
                    orderedListIndex: orderedListIndex
                )
            )

            if block.type == .orderedList {
                orderedListIndex += 1
            } else {
                orderedListIndex = 0
            }
        }

        return attributed
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
            return attributedSemanticParagraph(
                from: block.content,
                blockType: .codeBlock,
                baseFontSize: baseFontSize,
                presentationIntent: PresentationIntent(
                    .codeBlock(languageHint: nil),
                    identity: 1,
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
        let containerIntent = identitySource.make(containerKind, parent: semanticParent)
        let children = block.children ?? []
        var attributed = AttributedString()

        for (index, child) in children.enumerated() {
            if index > 0 {
                attributed.append(
                    attributedBoundary(for: block.type, baseFontSize: baseFontSize)
                )
            }
            let itemIntent = identitySource.make(
                .listItem(ordinal: index + 1),
                parent: containerIntent
            )
            let paragraphIntent = identitySource.make(.paragraph, parent: itemIntent)
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
        let quoteIntent = identitySource.make(.blockQuote, parent: semanticParent)
        let children = block.children ?? []
        var attributed = AttributedString()

        for (index, child) in children.enumerated() {
            if index > 0 {
                attributed.append(
                    attributedBoundary(for: .blockquote, baseFontSize: baseFontSize)
                )
            }
            let paragraphIntent = identitySource.make(.paragraph, parent: quoteIntent)
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

    private static func usesPresentationIntentProjection(
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

}

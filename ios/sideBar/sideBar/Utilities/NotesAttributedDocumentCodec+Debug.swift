import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension NotesAttributedDocumentCodec {
    static func debugSingleSemanticCodeBlockAttributedText(
        _ plainText: String,
        baseFontSize: CGFloat
    ) -> AttributedString {
        let identitySource = NotesPresentationIntentIdentitySource()
        return attributedBlocks(
            from: [
                .init(
                    type: .codeBlock,
                    content: [.init(text: plainText, marks: [])]
                )
            ],
            baseFontSize: baseFontSize,
            identitySource: identitySource
        )
    }

    static func debugSingleSemanticCodeBlockAttributedBlockText(
        _ plainText: String,
        baseFontSize: CGFloat
    ) -> AttributedString {
        let identitySource = NotesPresentationIntentIdentitySource()
        return attributedBlock(
            from: .init(
                type: .codeBlock,
                content: [.init(text: plainText, marks: [])]
            ),
            baseFontSize: baseFontSize,
            identitySource: identitySource,
            semanticParent: nil
        )
    }

    static func debugCopiedBridgedPresentationIntentText(
        _ plainText: String,
        presentationIntent: PresentationIntent
    ) -> AttributedString {
        let blockAttributed = bridgedFoundationPresentationIntentText(
            plainText,
            presentationIntent: presentationIntent
        )
        var attributed = AttributedString()
        if attributed.characters.isEmpty {
            attributed = blockAttributed
        }
        return attributed
    }

    static func debugIdentitySourceBridgeCodeBlockText(
        _ plainText: String
    ) -> AttributedString {
        let identitySource = NotesPresentationIntentIdentitySource()
        return bridgedFoundationPresentationIntentText(
            plainText,
            presentationIntent: PresentationIntent(
                .codeBlock(languageHint: nil),
                identity: identitySource.makeIdentity(),
                parent: nil
            )
        )
    }

    static func debugLocalBlockBridgeCodeBlockText(
        _ plainText: String
    ) -> AttributedString {
        let block = NotesSemanticDocument.Block(
            type: .codeBlock,
            content: [.init(text: plainText, marks: [])]
        )
        return bridgedFoundationPresentationIntentText(
            block.content.map(\.text).joined(),
            presentationIntent: PresentationIntent(
                .codeBlock(languageHint: nil),
                identity: 1,
                parent: nil
            )
        )
    }

    static func debugSwitchedLocalBlockBridgeCodeBlockText(
        _ plainText: String
    ) -> AttributedString {
        let block = NotesSemanticDocument.Block(
            type: .codeBlock,
            content: [.init(text: plainText, marks: [])]
        )

        switch block.type {
        case .codeBlock:
            return bridgedFoundationPresentationIntentText(
                block.content.map(\.text).joined(),
                presentationIntent: PresentationIntent(
                    .codeBlock(languageHint: nil),
                    identity: 1,
                    parent: nil
                )
            )
        default:
            return AttributedString("")
        }
    }

    static func debugCodecComposedTitleThenCodeBlockText(
        baseFontSize: CGFloat
    ) -> AttributedString {
        var attributed = attributedParagraph(
            from: [.init(text: "Snippet", marks: [])],
            blockType: .title,
            baseFontSize: baseFontSize
        )
        attributed.append(
            attributedBoundary(
                for: .codeBlock,
                baseFontSize: baseFontSize
            )
        )
        attributed.append(
            bridgedFoundationPresentationIntentText(
                "let value = 1",
                presentationIntent: PresentationIntent(
                    .codeBlock(languageHint: nil),
                    identity: 1,
                    parent: nil
                )
            )
        )
        return attributed
    }

    static func debugWrapperStyleTitleThenCodeBlockText(
        baseFontSize: CGFloat
    ) -> AttributedString {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let value = 1", marks: [])])
            ]
        )

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

    static func debugBlockArrayTitleThenCodeBlockText(
        baseFontSize: CGFloat
    ) -> AttributedString {
        let blocks: [NotesSemanticDocument.Block] = [
            .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
            .init(type: .codeBlock, content: [.init(text: "let value = 1", marks: [])])
        ]
        let identitySource = NotesPresentationIntentIdentitySource()
        return attributedBlocks(
            from: blocks,
            baseFontSize: baseFontSize,
            identitySource: identitySource
        )
    }
}

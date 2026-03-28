import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct NotesPresentationIntentIdentitySource {
    private var nextIdentity = 1

    mutating func makeIdentity() -> Int {
        let identity = nextIdentity
        nextIdentity += 1
        return identity
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
            var identitySource = NotesPresentationIntentIdentitySource()
            attributed = attributedBlocks(
                from: document.blocks,
                baseFontSize: baseFontSize,
                identitySource: &identitySource
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

    static func attributedBoundary(
        for blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat
    ) -> AttributedString {
        attributedBoundary(
            after: nil,
            before: blockType,
            baseFontSize: baseFontSize
        )
    }

    static func attributedBoundary(
        after previousBlockType: NotesSemanticDocument.BlockType?,
        before nextBlockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat
    ) -> AttributedString {
        var boundary = AttributedString("\n")
        let range = boundary.startIndex..<boundary.endIndex
        boundary[range].font = blockFont(
            baseFontSize: baseFontSize,
            blockType: nextBlockType,
            bold: false,
            italic: false
        )
        #if os(iOS)
        boundary[range][AttributeScopes.UIKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: nextBlockType,
                bold: false,
                italic: false
            )
        #elseif os(macOS)
        boundary[range][AttributeScopes.AppKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: nextBlockType,
                bold: false,
                italic: false
            )
        #endif
        let boundaryOwner = previousBlockType ?? nextBlockType
        let additionalSpacingAfter: CGFloat
        if previousBlockType == .codeBlock {
            additionalSpacingAfter = NoteTextParagraphMetrics.codeBlockPaddingAfter(
                baseFontSize: baseFontSize
            )
        } else if nextBlockType == .codeBlock {
            additionalSpacingAfter = NoteTextParagraphMetrics.codeBlockPaddingBefore(
                baseFontSize: baseFontSize
            )
        } else {
            additionalSpacingAfter = 0
        }
        boundary[range].paragraphStyle = paragraphStyle(
            for: boundaryOwner,
            baseFontSize: baseFontSize,
            additionalSpacingAfter: additionalSpacingAfter
        )
        boundary[range].noteBlock = blockMarker(for: nextBlockType)
        boundary[range].noteStructuralBoundary = true
        return boundary
    }

    static func attributedParagraph(
        from segments: [NotesSemanticDocument.InlineSegment],
        blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        additionalSpacingBefore: CGFloat = 0,
        additionalSpacingAfter: CGFloat = 0,
        visiblePrefix: String? = nil
    ) -> AttributedString {
        var paragraph = AttributedString()
        let paragraphStyle = paragraphStyle(
            for: blockType,
            baseFontSize: baseFontSize,
            additionalSpacingBefore: additionalSpacingBefore,
            additionalSpacingAfter: additionalSpacingAfter
        )

        if let visiblePrefix {
            paragraph.append(
                styledParagraphPiece(
                    visiblePrefix,
                    blockType: blockType,
                    baseFontSize: baseFontSize,
                    paragraphStyle: paragraphStyle
                )
            )
        }

        for segment in segments {
            paragraph.append(
                styledParagraphPiece(
                    segment,
                    blockType: blockType,
                    baseFontSize: baseFontSize,
                    paragraphStyle: paragraphStyle
                )
            )
        }

        return paragraph
    }

    static func attributedSemanticParagraph(
        from segments: [NotesSemanticDocument.InlineSegment],
        blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        visiblePrefix: String? = nil,
        presentationIntent: PresentationIntent
    ) -> AttributedString {
        var paragraph = attributedParagraph(
            from: segments,
            blockType: blockType,
            baseFontSize: baseFontSize,
            visiblePrefix: visiblePrefix
        )
        guard !paragraph.characters.isEmpty else { return paragraph }
        let range = paragraph.startIndex..<paragraph.endIndex
        paragraph[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
            presentationIntent
        return paragraph
    }

    static func styledPresentationIntentText(
        _ plainText: String,
        blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        additionalSpacingBefore: CGFloat = 0,
        additionalSpacingAfter: CGFloat = 0,
        presentationIntent: PresentationIntent
    ) -> AttributedString {
        var attributed = bridgedFoundationPresentationIntentText(
            plainText,
            presentationIntent: presentationIntent
        )
        guard !attributed.characters.isEmpty else { return attributed }

        let range = attributed.startIndex..<attributed.endIndex
        attributed[range].font = blockFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: false,
            italic: false
        )
        #if os(iOS)
        attributed[range][AttributeScopes.UIKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: blockType,
                bold: false,
                italic: false
            )
        attributed[range][AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] =
            NoteTextAppearance.backgroundColor(
                for: blockType,
                inlineCode: false
            )
        #elseif os(macOS)
        attributed[range][AttributeScopes.AppKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: blockType,
                bold: false,
                italic: false
            )
        attributed[range][AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] =
            NoteTextAppearance.backgroundColor(
                for: blockType,
                inlineCode: false
            )
        #endif
        attributed[range].paragraphStyle = paragraphStyle(
            for: blockType,
            baseFontSize: baseFontSize,
            additionalSpacingBefore: additionalSpacingBefore,
            additionalSpacingAfter: additionalSpacingAfter
        )
        if let blockMarker = blockMarker(for: blockType) {
            attributed[range].noteBlock = blockMarker
        }
        return attributed
    }

    static func bridgedFoundationPresentationIntentText(
        _ plainText: String,
        presentationIntent: PresentationIntent
    ) -> AttributedString {
        var attributed = AttributedString(plainText)
        if !attributed.characters.isEmpty {
            let range = attributed.startIndex..<attributed.endIndex
            attributed[range][
                AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self
            ] = presentationIntent
        }
        return attributed
    }

    private static func styledParagraphPiece(
        _ text: String,
        blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        paragraphStyle: NSParagraphStyle
    ) -> AttributedString {
        var piece = AttributedString(text)
        guard !piece.characters.isEmpty else { return piece }

        let range = piece.startIndex..<piece.endIndex
        piece[range].font = blockFont(
            baseFontSize: baseFontSize,
            blockType: blockType,
            bold: false,
            italic: false
        )
        #if os(iOS)
        piece[range][AttributeScopes.UIKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: blockType,
                bold: false,
                italic: false
            )
        #elseif os(macOS)
        piece[range][AttributeScopes.AppKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: blockType,
                bold: false,
                italic: false
            )
        #endif
        piece[range].paragraphStyle = paragraphStyle
        if let blockMarker = blockMarker(for: blockType) {
            piece[range].noteBlock = blockMarker
        }
        return piece
    }

    private static func styledParagraphPiece(
        _ segment: NotesSemanticDocument.InlineSegment,
        blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        paragraphStyle: NSParagraphStyle
    ) -> AttributedString {
        var piece = AttributedString(segment.text)
        guard !piece.characters.isEmpty else { return piece }

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
        piece[range].strikethroughStyle = marks.contains(.strikethrough) ? .single : nil
        piece[range].link = segment.link.flatMap { URL(string: $0.url) }
        piece[range].paragraphStyle = paragraphStyle
        if let blockMarker = blockMarker(for: blockType) {
            piece[range].noteBlock = blockMarker
        }
        return piece
    }
}

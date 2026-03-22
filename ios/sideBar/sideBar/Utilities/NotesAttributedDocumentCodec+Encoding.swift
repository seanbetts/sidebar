import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
final class NotesPresentationIntentIdentitySource {
    private var nextIdentity = 1

    func makeIdentity() -> Int {
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
        return bridgedFoundationPresentationIntentText(
            plainText,
            presentationIntent: presentationIntent
        )
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
}

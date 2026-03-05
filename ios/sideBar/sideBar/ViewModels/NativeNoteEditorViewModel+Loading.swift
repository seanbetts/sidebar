@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    public func loadText(_ text: String) {
        let canonical = NotesRichTextCodec.encodePlainTextToBase64RTF(text)
        var detectedContent =
            NotesRichTextCodec.decodeBase64RTFToAttributedString(canonical)
            ?? AttributedString(text)
        _ = applyDetectedLinks(in: &detectedContent)
        attributedContent = detectedContent
        selection = AttributedTextSelection()
        normalizeDocumentStylingForDisplay()
        lastSavedContent = text
        lastSavedCanonicalContent =
            NotesRichTextCodec.encodeAttributedStringToBase64RTF(attributedContent)
            ?? NotesRichTextCodec.encodePlainTextToBase64RTF(text)
        hasUnsavedChanges = false
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
    }

    func normalizeDocumentStylingForDisplay() {
        guard !attributedContent.characters.isEmpty else { return }

        var normalized = attributedContent
        stripUnsupportedInlineStyles(in: &normalized)
        for line in lineInfos(in: normalized) {
            let lineRange = attributedRange(for: line.range, in: normalized)
            let resolvedBlockKind: BlockKind = .paragraph
            normalized[lineRange].blockKind = resolvedBlockKind
            normalized[lineRange].listDepth = nil
            normalized[lineRange].codeLanguage = nil
            normalized[lineRange].inlineMarker = nil
            normalized[lineRange].listMarker = nil
            normalized[lineRange][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
            normalized[lineRange][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
            applyInlineIntentStyling(in: &normalized, lineRange: lineRange, blockKind: resolvedBlockKind)
            let paragraphRange = lineRangeIncludingTrailingNewline(in: normalized, lineRange: lineRange)
            normalized[paragraphRange].paragraphStyle = NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize
            )
        }

        if normalized != attributedContent {
            attributedContent = normalized
        }
    }
}

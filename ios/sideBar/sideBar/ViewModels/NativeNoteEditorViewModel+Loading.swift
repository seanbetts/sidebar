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
        for line in lineInfos(in: normalized) {
            let lineRange = attributedRange(for: line.range, in: normalized)
            let resolvedBlockKind = normalized.blockKind(in: lineRange)
                ?? (line.text.isEmpty ? .blankLine : .paragraph)
            normalized[lineRange].blockKind = resolvedBlockKind
            if isListBlockKind(resolvedBlockKind) {
                normalized[lineRange].listDepth = max(1, normalized[lineRange].listDepth ?? 1)
            } else {
                normalized[lineRange].listDepth = nil
            }
            if resolvedBlockKind != .codeBlock {
                normalized[lineRange].codeLanguage = nil
            }
            applyInlineIntentStyling(in: &normalized, lineRange: lineRange, blockKind: resolvedBlockKind)
            let paragraphRange = lineRangeIncludingTrailingNewline(in: normalized, lineRange: lineRange)
            let listDepth = normalized[lineRange].listDepth
            if let style = paragraphStyle(for: resolvedBlockKind, listDepth: listDepth) {
                normalized[paragraphRange].paragraphStyle = style
            }
        }

        if normalized != attributedContent {
            attributedContent = normalized
        }
    }
}

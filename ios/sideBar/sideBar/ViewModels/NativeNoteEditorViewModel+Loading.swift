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
        attributedContent = normalizedEditorDocumentForRuntime(from: detectedContent)
        selection = AttributedTextSelection()
        lastSavedContent = text
        lastSavedCanonicalContent =
            NotesRichTextCodec.encodeAttributedStringToBase64RTF(attributedContent)
            ?? NotesRichTextCodec.encodePlainTextToBase64RTF(text)
        hasUnsavedChanges = false
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
    }

    func normalizeDocumentStylingForDisplay() {
        let normalized = normalizedEditorDocumentForRuntime(from: attributedContent)
        if normalized != attributedContent {
            attributedContent = normalized
        }
    }
}

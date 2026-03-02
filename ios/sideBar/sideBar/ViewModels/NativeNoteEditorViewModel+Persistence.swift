@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    public func loadDocument(canonicalContent: String, plainText: String) {
        if let attributed = NotesRichTextCodec.decodeBase64RTFToAttributedString(canonicalContent) {
            var detectedContent = attributed
            _ = applyDetectedLinks(in: &detectedContent)
            attributedContent = detectedContent
            selection = AttributedTextSelection()
            lastSavedContent = plainText
            lastSavedCanonicalContent = canonicalContent
            hasUnsavedChanges = false
            lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
            updatePrefixVisibility()
            return
        }
        loadText(plainText)
    }

    public func currentCanonicalContent() -> String {
        if let encoded = NotesRichTextCodec.encodeAttributedStringToBase64RTF(attributedContent) {
            return encoded
        }
        return NotesRichTextCodec.encodePlainTextToBase64RTF(currentPlainText())
    }

    public func markSaved(plainText: String) {
        markSaved(plainText: plainText, canonicalContent: currentCanonicalContent())
    }

    public func markSaved(plainText: String, canonicalContent: String) {
        lastSavedContent = plainText
        lastSavedCanonicalContent = canonicalContent
        hasUnsavedChanges = false
    }
}

@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    /// Canonical rich text and plain-text values captured from one editor state snapshot.
    public struct PersistenceSnapshot {
        public let canonicalContent: String
        public let plainText: String
    }

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
            return
        }
        loadText(plainText)
    }

    public func currentPersistenceSnapshot() -> PersistenceSnapshot {
        let plainText = currentPlainText()
        if let canonicalContent = NotesRichTextCodec.encodeAttributedStringToBase64RTF(attributedContent) {
            return PersistenceSnapshot(canonicalContent: canonicalContent, plainText: plainText)
        }
        return PersistenceSnapshot(
            canonicalContent: NotesRichTextCodec.encodePlainTextToBase64RTF(plainText),
            plainText: plainText
        )
    }

    public func currentCanonicalContent() -> String {
        currentPersistenceSnapshot().canonicalContent
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

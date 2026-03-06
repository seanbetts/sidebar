@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    /// Canonical rich text and plain-text values captured from one editor state snapshot.
    public struct PersistenceSnapshot {
        public let document: NotesSemanticDocument
        public let canonicalContent: String
        public let plainText: String
    }

    public func loadDocument(canonicalContent: String, plainText: String) {
        if let attributed = NotesRichTextCodec.decodeBase64RTFToAttributedString(canonicalContent) {
            let document = NotesAttributedDocumentCodec.document(from: attributed)
            var loadedContent = NotesAttributedDocumentCodec.attributedString(
                from: document,
                baseFontSize: baseFontSize
            )
            constrainEditorDocument(&loadedContent)
            attributedContent = loadedContent
            selection = AttributedTextSelection()
            let snapshot = currentPersistenceSnapshot()
            lastSavedContent = snapshot.plainText
            lastSavedCanonicalContent = snapshot.canonicalContent
            hasUnsavedChanges = false
            lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
            return
        }
        loadText(plainText)
    }

    public func currentPersistenceSnapshot() -> PersistenceSnapshot {
        let document = NotesAttributedDocumentCodec.document(
            from: constrainedEditorDocument(from: attributedContent)
        )
        let plainText = NotesSemanticDocumentProjection.plainText(from: document)
        let exportContent = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: baseFontSize
        )
        if let canonicalContent = NotesRichTextCodec.encodeAttributedStringToBase64RTF(
            exportContent,
            baseFontSize: baseFontSize
        ) {
            return PersistenceSnapshot(
                document: document,
                canonicalContent: canonicalContent,
                plainText: plainText
            )
        }
        return PersistenceSnapshot(
            document: document,
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

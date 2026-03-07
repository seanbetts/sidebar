@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    /// Canonical semantic document and plain-text values captured from one editor state snapshot.
    public struct PersistenceSnapshot {
        public let document: NotesSemanticDocument
        public let canonicalContent: String
        public let plainText: String
    }

    public func loadDocument(canonicalContent: String, plainText: String) {
        let document = NotesSemanticDocumentCodec.decode(canonicalContent)
            ?? NotesSemanticDocumentProjection.document(fromPlainText: plainText)
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
    }

    public func currentPersistenceSnapshot() -> PersistenceSnapshot {
        let document = NotesAttributedDocumentCodec.document(
            from: constrainedEditorDocument(from: attributedContent)
        )
        let plainText = NotesSemanticDocumentProjection.plainText(from: document)
        return PersistenceSnapshot(
            document: document,
            canonicalContent: NotesSemanticDocumentCodec.encode(document) ?? "",
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

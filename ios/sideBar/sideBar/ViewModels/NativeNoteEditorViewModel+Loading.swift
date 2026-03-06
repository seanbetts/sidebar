@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    public func loadText(_ text: String) {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: text)
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

    func normalizeDocumentStylingForDisplay() {
        let snapshot = selectionSnapshot(in: attributedContent)
        let normalized = constrainedEditorDocument(from: attributedContent)
        if normalized != attributedContent {
            attributedContent = normalized
            selection = selection(from: snapshot, in: normalized)
        }
    }
}

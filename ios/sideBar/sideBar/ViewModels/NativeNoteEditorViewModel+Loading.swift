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

    func replacePlainTextContent(
        _ text: String,
        selectedUTF16Range: NSRange
    ) {
        let previousContent = attributedContent
        let previousSelection = selection
        let document = NotesSemanticDocumentProjection.document(fromPlainText: text)
        var updatedContent = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: baseFontSize
        )
        constrainEditorDocument(&updatedContent)
        let updatedSelection = selection(fromUTF16Range: selectedUTF16Range, in: updatedContent)

        guard updatedContent != previousContent || updatedSelection != previousSelection else { return }

        attributedContent = updatedContent
        selection = updatedSelection
        handleContentChange(previous: previousContent)
        if updatedSelection != previousSelection {
            handleSelectionChange()
        }
    }

    func replaceAttributedContent(
        _ text: NSAttributedString,
        selectedUTF16Range: NSRange
    ) {
        let previousContent = attributedContent
        let previousSelection = selection
        var updatedContent = (try? AttributedString(text, including: \.noteTextEditor))
            ?? AttributedString(text)
        constrainEditorDocument(&updatedContent)
        let updatedSelection = selection(fromUTF16Range: selectedUTF16Range, in: updatedContent)

        guard updatedContent != previousContent || updatedSelection != previousSelection else { return }

        attributedContent = updatedContent
        selection = updatedSelection
        handleContentChange(previous: previousContent)
        if updatedSelection != previousSelection {
            handleSelectionChange()
        }
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

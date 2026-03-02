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
        if !attributedContent.characters.isEmpty {
            let fullRange = attributedContent.startIndex..<attributedContent.endIndex
            attributedContent[fullRange].blockKind = .paragraph
            attributedContent[fullRange].listDepth = nil
            setFont(
                baseFont(for: .paragraph),
                platformFont: platformBaseFont(for: .paragraph),
                in: &attributedContent,
                range: fullRange
            )
            setForegroundColor(baseForegroundColor(for: .paragraph), in: &attributedContent, range: fullRange)
            setBackgroundColor(baseBackgroundColor(for: .paragraph), in: &attributedContent, range: fullRange)
            if let style = paragraphStyle(for: .paragraph) {
                attributedContent[fullRange].paragraphStyle = style
            }
        }
        selection = AttributedTextSelection()
        lastSavedContent = text
        lastSavedCanonicalContent =
            NotesRichTextCodec.encodeAttributedStringToBase64RTF(detectedContent)
            ?? NotesRichTextCodec.encodePlainTextToBase64RTF(text)
        hasUnsavedChanges = false
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
        updatePrefixVisibility()
    }
}

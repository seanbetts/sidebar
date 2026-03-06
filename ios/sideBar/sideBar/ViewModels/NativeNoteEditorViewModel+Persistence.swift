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
            attributedContent = normalizedEditorDocumentForRuntime(from: detectedContent)
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
        var exportContent = normalizedEditorDocumentForRuntime(from: attributedContent)
        // Materialize inline styling before export so semantic editor state survives the RTF bridge.
        materializeExportFormatting(in: &exportContent)
        NoteTextFormattingDefinition().constrainDocument(&exportContent)
        let plainText = NotePlainTextProjection.plainText(from: exportContent)
        if let canonicalContent = NotesRichTextCodec.encodeAttributedStringToBase64RTF(exportContent) {
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

    private struct ExportInlineRun {
        let range: Range<Int>
        let blockKind: BlockKind?
        let bold: Bool
        let italic: Bool
        let underline: Bool
    }

    private func materializeExportFormatting(in text: inout AttributedString) {
        let runs = exportInlineRuns(in: text)
        for run in runs {
            let range = attributedRange(for: run.range, in: text)
            if run.bold || run.italic {
                let styledFont = inlineStyledFont(
                    blockKind: run.blockKind,
                    bold: run.bold,
                    italic: run.italic
                )
                let platformStyledFont = platformFontApplyingTraits(
                    platformBaseFont(for: run.blockKind),
                    bold: run.bold,
                    italic: run.italic
                )
                setFont(styledFont, platformFont: platformStyledFont, in: &text, range: range)
            }
            if run.underline {
                text[range].underlineStyle = .single
            }
        }
    }

    private func exportInlineRuns(in text: AttributedString) -> [ExportInlineRun] {
        text.runs.compactMap { run in
            guard !run.range.isEmpty else { return nil }
            let lower = text.characters.distance(from: text.startIndex, to: run.range.lowerBound)
            let upper = text.characters.distance(from: text.startIndex, to: run.range.upperBound)
            let state = canonicalInlineFormattingState(from: run)
            return ExportInlineRun(
                range: lower..<upper,
                blockKind: text.blockKind(in: run.range),
                bold: state.bold,
                italic: state.italic,
                underline: state.underline
            )
        }
    }
}

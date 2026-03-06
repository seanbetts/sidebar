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
            normalizeDocumentStylingForDisplay()
            lastSavedContent = plainText
            lastSavedCanonicalContent = canonicalContent
            hasUnsavedChanges = false
            lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
            return
        }
        loadText(plainText)
    }

    public func currentPersistenceSnapshot() -> PersistenceSnapshot {
        var exportContent = attributedContent
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
            let intents = run.inlinePresentationIntent ?? []
            let bold = intents.contains(.stronglyEmphasized)
                || swiftUIFontHasTrait(run.font, for: .stronglyEmphasized)
                || exportFontHasTrait(run, intent: .stronglyEmphasized)
            let italic = intents.contains(.emphasized)
                || swiftUIFontHasTrait(run.font, for: .emphasized)
                || exportFontHasTrait(run, intent: .emphasized)
            let underline = run.underlineStyle != nil
            return ExportInlineRun(
                range: lower..<upper,
                blockKind: text.blockKind(in: run.range),
                bold: bold,
                italic: italic,
                underline: underline
            )
        }
    }

    private func exportFontHasTrait(
        _ run: AttributedString.Runs.Run,
        intent: InlinePresentationIntent
    ) -> Bool {
        guard let font = exportPlatformFont(from: run) else { return false }
        switch intent {
        case .stronglyEmphasized:
            #if os(iOS)
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif os(macOS)
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        case .emphasized:
            #if os(iOS)
            return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            #elseif os(macOS)
            return font.fontDescriptor.symbolicTraits.contains(.italic)
            #endif
        default:
            return false
        }
    }

    private func exportPlatformFont(from run: AttributedString.Runs.Run) -> PlatformFont? {
        var sample = AttributedString("x")
        let sampleRange = sample.startIndex..<sample.endIndex
        sample[sampleRange].mergeAttributes(run.attributes)
        let bridged = (try? NSAttributedString(sample, including: \.attributedNoteTextSurface))
            ?? NSAttributedString(sample)
        guard bridged.length > 0 else { return nil }
        return bridged.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
    }
}

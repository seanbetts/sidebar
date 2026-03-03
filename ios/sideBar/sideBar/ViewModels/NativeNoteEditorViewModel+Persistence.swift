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
            if plainTextRuntimeModeEnabled {
                detectedContent = plainTextRuntimeNormalizedContent(from: detectedContent)
            } else {
                _ = applyDetectedLinks(in: &detectedContent)
            }
            attributedContent = detectedContent
            selection = AttributedTextSelection()
            if !plainTextRuntimeModeEnabled {
                normalizeDocumentStylingForDisplay()
            }
            lastSavedContent = plainText
            lastSavedCanonicalContent = canonicalContent
            hasUnsavedChanges = false
            lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
            return
        }
        loadText(plainText)
    }

    public func currentPersistenceSnapshot() -> PersistenceSnapshot {
        if plainTextRuntimeModeEnabled {
            let plainText = String(attributedContent.characters)
            guard enabledFormattingCapabilities.isEmpty else {
                var exportContent = attributedContent
                materializePersistenceInlineStyling(in: &exportContent)
                let exportPlainText = String(exportContent.characters)
                if let canonicalContent = NotesRichTextCodec.encodeAttributedStringToBase64RTF(exportContent) {
                    return PersistenceSnapshot(
                        canonicalContent: canonicalContent,
                        plainText: exportPlainText
                    )
                }
                return PersistenceSnapshot(
                    canonicalContent: NotesRichTextCodec.encodePlainTextToBase64RTF(exportPlainText),
                    plainText: exportPlainText
                )
            }
            return PersistenceSnapshot(
                canonicalContent: NotesRichTextCodec.encodePlainTextToBase64RTF(plainText),
                plainText: plainText
            )
        }

        var exportContent = attributedContent
        materializePersistenceInlineStyling(in: &exportContent)
        injectPersistenceListPrefixes(in: &exportContent)

        let plainText = String(exportContent.characters)
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

    private func materializePersistenceInlineStyling(in text: inout AttributedString) {
        let lines = lineInfos(in: text)
        for line in lines {
            let lineRange = attributedRange(for: line.range, in: text)
            let blockKind = text.blockKind(in: lineRange) ?? (line.text.isEmpty ? .blankLine : .paragraph)
            applyInlineIntentStyling(in: &text, lineRange: lineRange, blockKind: blockKind)
            let listDepth = text[lineRange].listDepth
            if let style = paragraphStyle(for: blockKind, listDepth: listDepth) {
                let paragraphRange = lineRangeIncludingTrailingNewline(in: text, lineRange: lineRange)
                text[paragraphRange].paragraphStyle = style
            }
        }
    }

    private func injectPersistenceListPrefixes(in text: inout AttributedString) {
        let lines = lineInfos(in: text)
        let orderedOrdinals = orderedListOrdinals(in: text, lines: lines)

        for (index, line) in lines.enumerated().reversed() {
            let lineRange = attributedRange(for: line.range, in: text)
            guard let blockKind = text.blockKind(in: lineRange), isListBlockKind(blockKind) else {
                continue
            }

            let ordinal = orderedOrdinals[index] ?? 1
            let prefix = persistenceListPrefix(blockKind: blockKind, ordinal: ordinal)
            guard !line.text.hasPrefix(prefix) else { continue }

            var marker = AttributedString(prefix)
            let markerRange = marker.startIndex..<marker.endIndex
            marker[markerRange].blockKind = blockKind
            marker[markerRange].listDepth = text[lineRange].listDepth
            setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &marker, range: markerRange)
            setForegroundColor(baseForegroundColor(for: blockKind), in: &marker, range: markerRange)
            setBackgroundColor(baseBackgroundColor(for: blockKind), in: &marker, range: markerRange)

            text.insert(marker, at: lineRange.lowerBound)
        }
    }

    private func persistenceListPrefix(blockKind: BlockKind, ordinal: Int) -> String {
        switch blockKind {
        case .orderedList:
            return "\(ordinal). "
        case .taskChecked:
            return "☑ "
        case .taskUnchecked:
            return "☐ "
        case .bulletList:
            return "• "
        default:
            return ""
        }
    }
}

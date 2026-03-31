import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
enum NotesAttributedDocumentCodec {}

@available(iOS 26.0, macOS 26.0, *)
extension NotesAttributedDocumentCodec {
    static func inlineMarks(
        from run: AttributedString.Runs.Run,
        blockType: NotesSemanticDocument.BlockType?
    ) -> [NotesSemanticDocument.InlineMark] {
        let formattingTraits = noteSemanticInlineFormattingTraits(
            from: run.attributes,
            blockType: blockType
        )
        return NotesSemanticDocument.InlineMark.storageOrder.compactMap { mark in
            switch mark {
            case .bold:
                return formattingTraits.bold ? .bold : nil
            case .italic:
                return formattingTraits.italic ? .italic : nil
            case .underline:
                return run.underlineStyle != nil ? .underline : nil
            case .strikethrough:
                guard run.noteChecklistCompletion != true else { return nil }
                return run.strikethroughStyle != nil ? .strikethrough : nil
            case .inlineCode:
                guard formattingTraits.monospaced, blockType != .some(.codeBlock) else {
                    return nil
                }
                return .inlineCode
            }
        }
    }

    static func shouldFlushBeforeProcessingRun(
        currentBlockMarker: String?,
        blockMarker: String?,
        hasBufferedContent: Bool
    ) -> Bool {
        guard hasBufferedContent else { return false }
        guard let blockMarker else { return false }
        return blockMarker != currentBlockMarker
    }

    static func shouldFlushCodeBlockBeforeSeparatorRun(
        currentBlockMarker: String?,
        blockMarker: String?,
        runText: String,
        hasBufferedContent: Bool
    ) -> Bool {
        guard hasBufferedContent else { return false }
        guard blockMarker == nil else { return false }
        guard NoteTextBlockAttribute.blockType(from: currentBlockMarker) == .codeBlock else {
            return false
        }
        return !runText.isEmpty && runText.allSatisfy(\.isNewline)
    }

    static func semanticLink(
        from run: AttributedString.Runs.Run
    ) -> NotesSemanticDocument.Link? {
        guard let url = run.link else { return nil }
        return .init(url: url.absoluteString)
    }

    static func applyingDetectedLinks(to attributed: AttributedString) -> AttributedString {
        let plainText = String(attributed.characters)
        guard !plainText.isEmpty,
              let detector = try? NSDataDetector(
                  types: NSTextCheckingResult.CheckingType.link.rawValue
              ) else {
            return attributed
        }

        let bridged = NSMutableAttributedString(
            attributedString: (try? NSAttributedString(attributed, including: \.noteTextEditor))
                ?? NSAttributedString(attributed)
        )
        let fullRange = NSRange(plainText.startIndex..<plainText.endIndex, in: plainText)

        detector.enumerateMatches(in: plainText, options: [], range: fullRange) { match, _, _ in
            guard let match,
                  let url = match.url,
                  match.range.location != NSNotFound else {
                return
            }
            bridged.addAttribute(.link, value: url, range: match.range)
        }

        return (try? AttributedString(bridged, including: \.noteTextEditor))
            ?? AttributedString(bridged)
    }

    static func orderedListPrefixLength(in text: String) -> Int {
        guard let range = text.range(of: #"^\d+\.\s"#, options: .regularExpression) else {
            return 0
        }
        return text.distance(from: text.startIndex, to: range.upperBound)
    }

    static func normalizedSegmentsAndCheckedState(
        from segments: [NotesSemanticDocument.InlineSegment],
        blockType: NotesSemanticDocument.BlockType
    ) -> (segments: [NotesSemanticDocument.InlineSegment], checked: Bool?) {
        let combinedText = segments.map(\.text).joined()
        switch blockType {
        case .unorderedList:
            let prefixLength: Int
            if combinedText.hasPrefix("- ") {
                prefixLength = 2
            } else if combinedText.hasPrefix("\u{2022} ") {
                prefixLength = 2
            } else {
                prefixLength = 0
            }
            return (
                droppingPrefixCharacters(
                    count: prefixLength,
                    from: segments
                ),
                nil
            )
        case .orderedList:
            return (
                droppingPrefixCharacters(
                    count: orderedListPrefixLength(in: combinedText),
                    from: segments
                ),
                nil
            )
        case .checklist:
            let checked = combinedText.hasPrefix("- [x] ")
            let prefixLength = (checked || combinedText.hasPrefix("- [ ] ")) ? 6 : 0
            return (
                droppingPrefixCharacters(count: prefixLength, from: segments),
                checked
            )
        case .blockquote:
            return (
                droppingPrefixCharacters(
                    count: combinedText.hasPrefix("> ") ? 2 : 0,
                    from: segments
                ),
                nil
            )
        default:
            return (segments, nil)
        }
    }

    static func droppingPrefixCharacters(
        count: Int,
        from segments: [NotesSemanticDocument.InlineSegment]
    ) -> [NotesSemanticDocument.InlineSegment] {
        guard count > 0 else { return segments }

        var remaining = count
        var normalized: [NotesSemanticDocument.InlineSegment] = []

        for segment in segments {
            guard remaining > 0 else {
                normalized.append(segment)
                continue
            }
            if segment.text.count <= remaining {
                remaining -= segment.text.count
                continue
            }
            let start = segment.text.index(segment.text.startIndex, offsetBy: remaining)
            normalized.append(
                .init(
                    text: String(segment.text[start...]),
                    marks: segment.marks,
                    link: segment.link
                )
            )
            remaining = 0
        }

        return normalized
    }
}

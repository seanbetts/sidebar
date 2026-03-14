import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
enum NotesAttributedDocumentCodec {
    static func attributedString(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> AttributedString {
        if let unsupportedContent = NotesUnsupportedContent.detect(in: document) {
            unsupportedContent.reportDetected(context: "NotesAttributedDocumentCodec.attributedString")
            return AttributedString("")
        }

        var attributed = AttributedString()
        var orderedListIndex = 0

        for (index, block) in document.blocks.enumerated() {
            if index > 0 {
                attributed.append(AttributedString("\n"))
            }

            attributed.append(
                attributedBlock(
                    from: block,
                    baseFontSize: baseFontSize,
                    orderedListIndex: orderedListIndex
                )
            )

            if block.type == .orderedList {
                orderedListIndex += 1
            } else {
                orderedListIndex = 0
            }
        }

        if attributed.characters.isEmpty {
            attributed = AttributedString("")
        }

        return attributed
    }

    static func readAttributedString(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> AttributedString {
        let attributed = attributedString(from: document, baseFontSize: baseFontSize)
        return applyingDetectedLinks(to: attributed)
    }

    static func document(from attributed: AttributedString) -> NotesSemanticDocument {
        var blocks: [NotesSemanticDocument.Block] = []
        var currentSegments: [NotesSemanticDocument.InlineSegment] = []
        var currentBlockMarker: String?

        func appendSegmentText(_ text: String, marks: [NotesSemanticDocument.InlineMark]) {
            guard !text.isEmpty else { return }
            if let last = currentSegments.last, last.marks == marks {
                currentSegments[currentSegments.count - 1] = .init(
                    text: last.text + text,
                    marks: last.marks
                )
            } else {
                currentSegments.append(.init(text: text, marks: marks))
            }
        }

        func flushBlock() {
            let resolvedBlockType = NoteTextBlockAttribute.blockType(from: currentBlockMarker)
                ?? (blocks.isEmpty ? .title : .paragraph)
            let normalized = normalizedSegmentsAndCheckedState(
                from: currentSegments,
                blockType: resolvedBlockType
            )
            var segments = normalized.segments
            if segments.isEmpty {
                segments = [.init(text: "", marks: [])]
            }
            blocks.append(
                .init(
                    type: resolvedBlockType,
                    content: segments,
                    checked: normalized.checked
                )
            )
            currentSegments.removeAll(keepingCapacity: true)
            currentBlockMarker = nil
        }

        for run in attributed.runs {
            let blockMarker = run.noteBlock
            if currentBlockMarker == nil {
                currentBlockMarker = blockMarker
            }
            let marks = inlineMarks(from: run)
            var buffer = ""
            for character in attributed[run.range].characters {
                if character.isNewline {
                    appendSegmentText(buffer, marks: marks)
                    buffer.removeAll(keepingCapacity: true)
                    flushBlock()
                } else {
                    buffer.append(character)
                }
            }
            appendSegmentText(buffer, marks: marks)
        }

        if blocks.isEmpty || !currentSegments.isEmpty {
            flushBlock()
        }

        return NotesSemanticDocument(blocks: blocks)
    }

    private static func attributedParagraph(
        from segments: [NotesSemanticDocument.InlineSegment],
        blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        visiblePrefix: String? = nil
    ) -> AttributedString {
        var paragraph = AttributedString()

        if let visiblePrefix {
            var prefix = AttributedString(visiblePrefix)
            if !prefix.characters.isEmpty {
                let range = prefix.startIndex..<prefix.endIndex
                prefix[range].font = blockFont(
                    baseFontSize: baseFontSize,
                    blockType: blockType,
                    bold: false,
                    italic: false
                )
                prefix[range].paragraphStyle = paragraphStyle(for: blockType, baseFontSize: baseFontSize)
                if let blockMarker = blockMarker(for: blockType) {
                    prefix[range].noteBlock = blockMarker
                }
            }
            paragraph.append(prefix)
        }

        for segment in segments {
            var piece = AttributedString(segment.text)
            if !piece.characters.isEmpty {
                let range = piece.startIndex..<piece.endIndex
                let marks = Set(segment.marks)
                piece[range].font = blockFont(
                    baseFontSize: baseFontSize,
                    blockType: blockType,
                    bold: marks.contains(.bold),
                    italic: marks.contains(.italic)
                )
                piece[range].underlineStyle = marks.contains(.underline) ? .single : nil
                piece[range].strikethroughStyle = marks.contains(.strikethrough) ? .single : nil
                piece[range].paragraphStyle = paragraphStyle(for: blockType, baseFontSize: baseFontSize)
                if let blockMarker = blockMarker(for: blockType) {
                    piece[range].noteBlock = blockMarker
                }
            }
            paragraph.append(piece)
        }

        return paragraph
    }

    private static func inlineMarks(
        from run: AttributedString.Runs.Run
    ) -> [NotesSemanticDocument.InlineMark] {
        let traits = noteSwiftUIFontTraits(from: noteExplicitSwiftUIFont(from: run.attributes))
        return NotesSemanticDocument.InlineMark.storageOrder.compactMap { mark in
            switch mark {
            case .bold:
                return traits.bold ? .bold : nil
            case .italic:
                return traits.italic ? .italic : nil
            case .underline:
                return run.underlineStyle != nil ? .underline : nil
            case .strikethrough:
                return run.strikethroughStyle != nil ? .strikethrough : nil
            case .inlineCode:
                return nil
            }
        }
    }

    private static func applyingDetectedLinks(to attributed: AttributedString) -> AttributedString {
        let plainText = String(attributed.characters)
        guard !plainText.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }

        let bridged = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        let fullRange = NSRange(plainText.startIndex..<plainText.endIndex, in: plainText)

        detector.enumerateMatches(in: plainText, options: [], range: fullRange) { match, _, _ in
            guard let match,
                  let url = match.url,
                  match.range.location != NSNotFound else {
                return
            }
            bridged.addAttribute(.link, value: url, range: match.range)
        }

        return AttributedString(bridged)
    }

    private static func attributedBlock(
        from block: NotesSemanticDocument.Block,
        baseFontSize: CGFloat,
        orderedListIndex: Int
    ) -> AttributedString {
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .listItem, .codeBlock:
            return attributedParagraph(
                from: block.content,
                blockType: block.type,
                baseFontSize: baseFontSize
            )
        case .unorderedList, .orderedList, .checklist, .blockquote:
            return attributedParagraph(
                from: block.content,
                blockType: block.type,
                baseFontSize: baseFontSize,
                visiblePrefix: visiblePrefix(for: block, orderedListIndex: orderedListIndex)
            )
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            assertionFailure("Unsupported block type should have been handled before rendering: \(block.type.rawValue)")
            return AttributedString("")
        }
    }

    private static func visiblePrefix(
        for block: NotesSemanticDocument.Block,
        orderedListIndex: Int
    ) -> String? {
        switch block.type {
        case .unorderedList:
            return "- "
        case .orderedList:
            return "\(orderedListIndex + 1). "
        case .checklist:
            return "- [\(block.checked == true ? "x" : " ")] "
        case .blockquote:
            return "> "
        default:
            return nil
        }
    }

    private static func blockMarker(
        for blockType: NotesSemanticDocument.BlockType
    ) -> String? {
        switch blockType {
        case .heading, .subheading, .unorderedList, .orderedList, .checklist, .listItem, .blockquote, .codeBlock:
            return blockType.rawValue
        case .title, .paragraph, .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            return nil
        }
    }

    private static func blockFont(
        baseFontSize: CGFloat,
        blockType: NotesSemanticDocument.BlockType,
        bold: Bool,
        italic: Bool
    ) -> Font {
        let size: CGFloat
        let design: Font.Design
        switch blockType {
        case .title:
            size = baseFontSize * 1.2
            design = .default
        case .heading:
            size = baseFontSize * 1.15
            design = .default
        case .subheading:
            size = baseFontSize * 1.08
            design = .default
        case .codeBlock:
            size = baseFontSize
            design = .monospaced
        default:
            size = baseFontSize
            design = .default
        }

        var font = Font.system(size: size, weight: bold ? .bold : .regular, design: design)
        if italic {
            font = font.italic()
        }
        return font
    }

    private static func paragraphStyle(
        for blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat
    ) -> NSParagraphStyle {
        switch blockType {
        case .unorderedList, .orderedList, .checklist:
            return NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: baseFontSize
            )
        case .blockquote:
            return NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 1.25
            )
        case .codeBlock:
            return NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 0.75,
                tailIndent: baseFontSize * 0.75
            )
        default:
            return NoteTextParagraphMetrics.bodyParagraphStyle(baseFontSize: baseFontSize)
        }
    }

    private static func normalizedSegmentsAndCheckedState(
        from segments: [NotesSemanticDocument.InlineSegment],
        blockType: NotesSemanticDocument.BlockType
    ) -> (segments: [NotesSemanticDocument.InlineSegment], checked: Bool?) {
        let combinedText = segments.map(\.text).joined()
        switch blockType {
        case .unorderedList:
            return (
                droppingPrefixCharacters(
                    count: combinedText.hasPrefix("- ") ? 2 : 0,
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

    private static func orderedListPrefixLength(in text: String) -> Int {
        guard let range = text.range(of: #"^\d+\. "#, options: .regularExpression) else {
            return 0
        }
        return text.distance(from: text.startIndex, to: range.upperBound)
    }

    private static func droppingPrefixCharacters(
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

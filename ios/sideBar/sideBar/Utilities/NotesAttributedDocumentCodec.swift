import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
enum NotesAttributedDocumentCodec {
    static func attributedString(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> AttributedString {
        var attributed = AttributedString()

        for (index, block) in document.blocks.enumerated() {
            if index > 0 {
                attributed.append(AttributedString("\n"))
            }

            switch block.type {
            case .paragraph:
                attributed.append(attributedParagraph(from: block.content, baseFontSize: baseFontSize))
            default:
                continue
            }
        }

        if attributed.characters.isEmpty {
            attributed = AttributedString("")
        }

        return attributed
    }

    static func document(from attributed: AttributedString) -> NotesSemanticDocument {
        var blocks: [NotesSemanticDocument.Block] = []
        var currentSegments: [NotesSemanticDocument.InlineSegment] = []

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

        func flushParagraph() {
            if currentSegments.isEmpty {
                currentSegments = [.init(text: "", marks: [])]
            }
            blocks.append(.paragraph(currentSegments))
            currentSegments.removeAll(keepingCapacity: true)
        }

        for run in attributed.runs {
            let marks = inlineMarks(from: run)
            var buffer = ""
            for character in attributed[run.range].characters {
                if character.isNewline {
                    appendSegmentText(buffer, marks: marks)
                    buffer.removeAll(keepingCapacity: true)
                    flushParagraph()
                } else {
                    buffer.append(character)
                }
            }
            appendSegmentText(buffer, marks: marks)
        }

        if blocks.isEmpty || !currentSegments.isEmpty {
            flushParagraph()
        }

        return NotesSemanticDocument(blocks: blocks)
    }

    private static func attributedParagraph(
        from segments: [NotesSemanticDocument.InlineSegment],
        baseFontSize: CGFloat
    ) -> AttributedString {
        var paragraph = AttributedString()

        for segment in segments {
            var piece = AttributedString(segment.text)
            if !piece.characters.isEmpty {
                let range = piece.startIndex..<piece.endIndex
                let marks = Set(segment.marks)
                piece[range].font = noteInlineFont(
                    baseFontSize: baseFontSize,
                    bold: marks.contains(.bold),
                    italic: marks.contains(.italic)
                )
                piece[range].underlineStyle = marks.contains(.underline) ? .single : nil
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
            }
        }
    }
}

@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func inlineMarksForStructuralInsertion() -> [NotesSemanticDocument.InlineMark] {
        let typingState = inlineFormattingState(
            from: typingAttributesForInsertion(in: attributedContent)
        )
        return NotesSemanticDocument.InlineMark.storageOrder.compactMap { mark in
            switch mark {
            case .bold:
                return typingState.bold ? .bold : nil
            case .italic:
                return typingState.italic ? .italic : nil
            case .underline:
                return typingState.underline ? .underline : nil
            case .strikethrough:
                return typingState.strikethrough ? .strikethrough : nil
            case .inlineCode:
                return typingState.inlineCode ? .inlineCode : nil
            }
        }
    }

    func appendSegmentText(
        _ text: String,
        marks: [NotesSemanticDocument.InlineMark],
        to segments: inout [NotesSemanticDocument.InlineSegment]
    ) {
        guard !text.isEmpty else { return }
        if let last = segments.last, last.marks == marks, last.link == nil {
            segments[segments.count - 1] = .init(text: last.text + text, marks: marks)
        } else {
            segments.append(.init(text: text, marks: marks))
        }
    }

    func appendSegments(
        _ appended: [NotesSemanticDocument.InlineSegment],
        to segments: inout [NotesSemanticDocument.InlineSegment]
    ) {
        for segment in appended {
            if let last = segments.last,
               last.marks == segment.marks,
               last.link == segment.link {
                segments[segments.count - 1] = .init(
                    text: last.text + segment.text,
                    marks: segment.marks,
                    link: segment.link
                )
            } else {
                segments.append(segment)
            }
        }
    }
}

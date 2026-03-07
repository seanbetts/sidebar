import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesLegacyMigrationService {
    private let api: any NotesProviding

    init(api: any NotesProviding) {
        self.api = api
    }

    func semanticDocument(
        fromLegacyContent content: String,
        fallbackPlainText: String
    ) -> NotesSemanticDocument? {
        if let attributed = NotesRichTextCodec.decodeLegacyBase64RTFToAttributedString(content) {
            return migrationDocument(from: attributed)
        }
        guard !fallbackPlainText.isEmpty else {
            return nil
        }
        return NotesSemanticDocumentProjection.document(fromPlainText: fallbackPlainText)
    }

    func semanticDocument(fromLegacyNote note: NotePayload) throws -> NotesSemanticDocument {
        semanticDocument(
            fromLegacyContent: try note.requireLegacyMigrationContent(),
            fallbackPlainText: note.plainText
        ) ?? NotesSemanticDocumentProjection.document(fromPlainText: note.plainText)
    }

    func migrateLegacyNote(id: String) async throws -> NotePayload {
        let note = try await api.getNote(id: id)
        return try await migrateLegacyNote(note)
    }

    func migrateLegacyNote(_ note: NotePayload) async throws -> NotePayload {
        guard note.hasLegacyMigrationContent else {
            return note
        }
        let document = try semanticDocument(fromLegacyNote: note)
        return try await api.updateNote(id: note.id, document: document)
    }
}

private extension NotePayload {
    func requireLegacyMigrationContent() throws -> String {
        if let content = legacyMigrationTransport?.content {
            return content
        }
        throw NotesLegacyMigrationError.missingLegacyTransport
    }

    var hasLegacyMigrationContent: Bool {
        legacyMigrationTransport?.contentFormat == "rtf"
    }
}

private enum NotesLegacyMigrationError: Error {
    case missingLegacyTransport
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private extension NotesLegacyMigrationService {
    func migrationDocument(from attributed: AttributedString) -> NotesSemanticDocument {
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
            let marks = migrationInlineMarks(from: run)
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

    func migrationInlineMarks(
        from run: AttributedString.Runs.Run
    ) -> [NotesSemanticDocument.InlineMark] {
        let swiftUIFontTraits = noteSwiftUIFontTraits(
            from: noteExplicitSwiftUIFont(from: run.attributes)
        )
        let platformTraits = noteBridgedPlatformFont(from: run.attributes)
            .map(notePlatformFontTraits(from:))
            ?? .plain
        let bold = swiftUIFontTraits.bold || platformTraits.bold
        let italic = swiftUIFontTraits.italic || platformTraits.italic
        return NotesSemanticDocument.InlineMark.storageOrder.compactMap { mark in
            switch mark {
            case .bold:
                return bold ? .bold : nil
            case .italic:
                return italic ? .italic : nil
            case .underline:
                return run.underlineStyle != nil ? .underline : nil
            }
        }
    }
}

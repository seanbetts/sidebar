import XCTest
import SwiftUI
@testable import sideBar

@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class NotesAttributedDocumentCodecTests: XCTestCase {
    func testSemanticParagraphDocumentEncodesCharactersOnly() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Hello", marks: [.bold]),
                    .init(text: " world", marks: [])
                ]),
                .paragraph([
                    .init(text: "Again", marks: [.italic, .underline])
                ])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: 18
        )

        XCTAssertEqual(String(attributed.characters), "Hello world\nAgain")
    }

    func testSingleParagraphBlockEncodesCharactersOnly() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Hello", marks: [.bold]),
                    .init(text: " world", marks: [])
                ])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: 18
        )

        XCTAssertEqual(String(attributed.characters), "Hello world")
    }

    func testCodeBlockEncodesCharactersOnlyWithoutInspectingIntent() {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let value = 1", marks: [])])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(from: document, baseFontSize: 16)

        XCTAssertEqual(String(attributed.characters), "Snippet\nlet value = 1")
    }

    func testStandaloneCodeBlockDocumentEncodesCharactersOnly() {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .codeBlock, content: [.init(text: "let value = 1", marks: [])])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(from: document, baseFontSize: 16)

        XCTAssertEqual(String(attributed.characters), "let value = 1")
    }

    func testSemanticParagraphDocumentProjectsToAttributedString() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Hello", marks: [.bold]),
                    .init(text: " world", marks: [])
                ]),
                .paragraph([
                    .init(text: "Again", marks: [.italic, .underline])
                ])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: 18
        )

        XCTAssertEqual(String(attributed.characters), "Hello world\nAgain")
        XCTAssertTrue(noteRangeHasBoldTrait(attributed, range: noteCharacterRange(length: 5, in: attributed)))

        let secondParagraphStart = attributed.index(attributed.startIndex, offsetByCharacters: 12)
        let secondParagraphEnd = attributed.index(secondParagraphStart, offsetByCharacters: 5)
        XCTAssertTrue(noteRangeHasItalicTrait(attributed, range: secondParagraphStart..<secondParagraphEnd))
        XCTAssertTrue(noteRangeIsUnderlined(attributed, range: secondParagraphStart..<secondParagraphEnd))
    }

    func testAttributedStringProjectsToSemanticDocumentWithTitleFirstBlock() {
        var attributed = AttributedString("Hello world\nAgain")
        let helloRange = noteCharacterRange(length: 5, in: attributed)
        attributed[helloRange].font = noteInlineFont(baseFontSize: 16, bold: true, italic: true)

        let againStart = attributed.index(attributed.startIndex, offsetByCharacters: 12)
        let againEnd = attributed.index(againStart, offsetByCharacters: 5)
        attributed[againStart..<againEnd].underlineStyle = .single

        let document = NotesAttributedDocumentCodec.document(from: attributed)

        XCTAssertEqual(
            document,
            NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [
                        .init(text: "Hello", marks: [.bold, .italic]),
                        .init(text: " world", marks: [])
                    ]),
                    .paragraph([
                        .init(text: "Again", marks: [.underline])
                    ])
                ]
            )
        )
    }

    func testInlineMarksRoundTripThroughSemanticDocumentCodec() {
        var attributed = AttributedString("Bold Italic Underline")

        let boldEnd = attributed.index(attributed.startIndex, offsetByCharacters: 4)
        attributed[attributed.startIndex..<boldEnd].font = noteInlineFont(baseFontSize: 16, bold: true, italic: false)

        let italicStart = attributed.index(attributed.startIndex, offsetByCharacters: 5)
        let italicEnd = attributed.index(italicStart, offsetByCharacters: 6)
        attributed[italicStart..<italicEnd].font = noteInlineFont(baseFontSize: 16, bold: false, italic: true)

        let underlineStart = attributed.index(attributed.startIndex, offsetByCharacters: 12)
        let underlineEnd = attributed.index(underlineStart, offsetByCharacters: 9)
        attributed[underlineStart..<underlineEnd].underlineStyle = .single

        let document = NotesAttributedDocumentCodec.document(from: attributed)
        let roundTrip = NotesAttributedDocumentCodec.attributedString(from: document, baseFontSize: 16)

        XCTAssertEqual(String(roundTrip.characters), "Bold Italic Underline")
        XCTAssertTrue(noteRangeHasBoldTrait(roundTrip, range: noteCharacterRange(length: 4, in: roundTrip)))

        let roundTripItalicStart = roundTrip.index(roundTrip.startIndex, offsetByCharacters: 5)
        let roundTripItalicEnd = roundTrip.index(roundTripItalicStart, offsetByCharacters: 6)
        XCTAssertTrue(noteRangeHasItalicTrait(roundTrip, range: roundTripItalicStart..<roundTripItalicEnd))

        let roundTripUnderlineStart = roundTrip.index(roundTrip.startIndex, offsetByCharacters: 12)
        let roundTripUnderlineEnd = roundTrip.index(roundTripUnderlineStart, offsetByCharacters: 9)
        XCTAssertTrue(noteRangeIsUnderlined(roundTrip, range: roundTripUnderlineStart..<roundTripUnderlineEnd))
    }

    func testCanonicalLinksRoundTripThroughSemanticDocumentCodec() throws {
        var attributed = AttributedString("OpenAI Docs")
        let linkRange = noteCharacterRange(length: 11, in: attributed)
        let url = try XCTUnwrap(URL(string: "https://platform.openai.com/docs"))

        attributed[linkRange].font = noteInlineFont(baseFontSize: 16, bold: true, italic: false)
        attributed[linkRange].link = url

        let document = NotesAttributedDocumentCodec.document(from: attributed)

        XCTAssertEqual(
            document,
            NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(
                        type: .title,
                        content: [
                            .init(
                                text: "OpenAI Docs",
                                marks: [.bold],
                                link: .init(url: url.absoluteString)
                            )
                        ]
                    )
                ]
            )
        )

        let roundTrip = NotesAttributedDocumentCodec.attributedString(from: document, baseFontSize: 16)

        XCTAssertEqual(String(roundTrip.characters), "OpenAI Docs")
        XCTAssertTrue(noteRangeHasBoldTrait(roundTrip, range: noteCharacterRange(length: 11, in: roundTrip)))
        XCTAssertEqual(noteLinkValue(in: roundTrip, atCharacterOffset: 0), url)
    }

    func testInlineCodeRoundTripsThroughSemanticDocumentCodec() {
        var attributed = AttributedString("code")
        let range = noteCharacterRange(length: 4, in: attributed)
        attributed[range].font = .system(size: 16, design: .monospaced)
        #if os(iOS)
        attributed[range][AttributeScopes.UIKitAttributes.FontAttribute.self] = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        #elseif os(macOS)
        attributed[range][AttributeScopes.AppKitAttributes.FontAttribute.self] = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        #endif

        let document = NotesAttributedDocumentCodec.document(from: attributed)
        let roundTrip = NotesAttributedDocumentCodec.attributedString(from: document, baseFontSize: 16)

        XCTAssertEqual(
            document,
            NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "code", marks: [.inlineCode])])
                ]
            )
        )
        XCTAssertTrue(noteRangeUsesMonospacedPlatformFont(roundTrip, range: noteCharacterRange(length: 4, in: roundTrip)))
        XCTAssertTrue(noteRangeHasInlineCodeBackground(roundTrip, range: noteCharacterRange(length: 4, in: roundTrip)))
    }

    func testCodeBlockRoundTripsMultilineLiteralContent() {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1\nprint(x)", marks: [])])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(from: document, baseFontSize: 16)
        let roundTrip = NotesAttributedDocumentCodec.document(from: attributed)

        XCTAssertEqual(String(attributed.characters), "Snippet\nlet x = 1\nprint(x)")
        let codeStart = attributed.index(attributed.startIndex, offsetByCharacters: 8)
        XCTAssertTrue(noteRangeUsesMonospacedPlatformFont(attributed, range: codeStart..<attributed.endIndex))
        XCTAssertEqual(roundTrip, document)
    }

    func testCodeBlockProjectsFoundationPresentationIntent() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let value = 1", marks: [])])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(from: document, baseFontSize: 16)
        let intent = try XCTUnwrap(notePresentationIntent(in: attributed, atCharacterOffset: 8))

        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testOrderedListContainerProjectsAndRoundTripsUsingPresentationIntent() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .orderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Second", marks: [])])
                    ]
                )
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(from: document, baseFontSize: 16)
        let firstIntent = try XCTUnwrap(notePresentationIntent(in: attributed, atCharacterOffset: 8))
        let secondIntent = try XCTUnwrap(notePresentationIntent(in: attributed, atCharacterOffset: 17))

        XCTAssertEqual(
            firstIntent.components.map(\.kind),
            [.orderedList, .listItem(ordinal: 1), .paragraph]
        )
        XCTAssertEqual(
            secondIntent.components.map(\.kind),
            [.orderedList, .listItem(ordinal: 2), .paragraph]
        )
        XCTAssertEqual(NotesAttributedDocumentCodec.document(from: attributed), document)
    }

    func testCodeBlockFollowedByParagraphRoundTripsAcrossSeparatorBoundary() {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1\n", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(from: document, baseFontSize: 16)
        let roundTrip = NotesAttributedDocumentCodec.document(from: attributed)

        XCTAssertEqual(roundTrip, document)
    }

    func testTrailingBlankParagraphRoundTripsAtEndOfAttributedString() {
        let attributed = AttributedString("Body\n")

        let document = NotesAttributedDocumentCodec.document(from: attributed)

        XCTAssertEqual(
            document,
            NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Body", marks: [])]),
                    .paragraph([.init(text: "", marks: [])])
                ]
            )
        )
    }

    func testSupportedBlockTypesRoundTripWithoutUnsupportedBoundary() {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])]),
                .init(type: .unorderedList, content: [.init(text: "Bullet item", marks: [])]),
                .init(type: .orderedList, content: [.init(text: "Ordered item", marks: [])]),
                .init(type: .checklist, content: [.init(text: "Checked item", marks: [])], checked: true),
                .init(type: .blockquote, content: [.init(text: "Quoted", marks: [.italic])]),
                .init(type: .codeBlock, content: [.init(text: "let value = 1", marks: [])])
            ]
        )

        XCTAssertNil(NotesUnsupportedContent.detect(in: document))

        let attributed = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: 18
        )

        XCTAssertEqual(NotesAttributedDocumentCodec.document(from: attributed), document)
    }

    func testBlockTypographyDoesNotRoundTripAsInlineBoldMarks() {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: 18
        )
        let roundTrip = NotesAttributedDocumentCodec.document(from: attributed)

        XCTAssertEqual(roundTrip, document)
    }

    func testInterBlockNewlinesCarryFollowingBlockOwnership() {
        let baseFontSize: CGFloat = 18
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subhead", marks: [])]),
                .paragraph([.init(text: "", marks: [])])
            ]
        )

        let attributed = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: baseFontSize
        )

        XCTAssertEqual(String(attributed.characters), "Title\nHeading\nSubhead\n")
        XCTAssertEqual(
            noteBlockValue(in: attributed, atCharacterOffset: 5),
            NotesSemanticDocument.BlockType.heading.rawValue
        )
        XCTAssertEqual(
            noteParagraphStyle(in: attributed, atCharacterOffset: 5),
            NoteTextParagraphMetrics.paragraphStyle(for: .heading, baseFontSize: baseFontSize)
        )
        XCTAssertEqual(
            noteBlockValue(in: attributed, atCharacterOffset: 13),
            NotesSemanticDocument.BlockType.subheading.rawValue
        )
        XCTAssertEqual(
            noteParagraphStyle(in: attributed, atCharacterOffset: 13),
            NoteTextParagraphMetrics.paragraphStyle(for: .subheading, baseFontSize: baseFontSize)
        )
        XCTAssertEqual(
            noteBlockValue(in: attributed, atCharacterOffset: 21),
            NotesSemanticDocument.BlockType.paragraph.rawValue
        )
        XCTAssertEqual(
            noteParagraphStyle(in: attributed, atCharacterOffset: 21),
            NoteTextParagraphMetrics.paragraphStyle(for: .paragraph, baseFontSize: baseFontSize)
        )
    }

    func testTableBlocksRemainUnsupported() {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .table, content: [.init(text: "Cell", marks: [])])
            ]
        )

        XCTAssertEqual(NotesUnsupportedContent.detect(in: document)?.blockTypes, [.table])
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func notePresentationIntent(
    in text: AttributedString,
    atCharacterOffset offset: Int
) -> PresentationIntent? {
    guard offset >= 0, offset < text.characters.count else { return nil }
    let lower = text.index(text.startIndex, offsetByCharacters: offset)
    let upper = text.index(afterCharacter: lower)
    return text[lower..<upper].runs.first?.attributes[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
}

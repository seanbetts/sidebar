import XCTest
import SwiftUI
@testable import sideBar

@available(iOS 26.0, macOS 26.0, *)
final class NotesAttributedDocumentCodecTests: XCTestCase {
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

    func testAttributedStringProjectsToSemanticParagraphDocument() {
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
                    .paragraph([
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
}

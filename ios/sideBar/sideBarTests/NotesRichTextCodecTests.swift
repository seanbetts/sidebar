import Foundation
import XCTest
@testable import sideBar

final class NotesRichTextCodecTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        let text = "Hello\nWorld"
        let encoded = NotesRichTextCodec.encodePlainTextToBase64RTF(text)
        let decoded = NotesRichTextCodec.decodeBase64RTFToPlainText(encoded)

        XCTAssertEqual(decoded, text)
    }

    func testNormalizeWriteInputUsesExplicitPlainText() {
        let normalized = NotesRichTextCodec.normalizeWriteInput(
            content: "ignored",
            plainText: "Body"
        )

        XCTAssertEqual(normalized.plainText, "Body")
        XCTAssertNotNil(NotesRichTextCodec.decodeBase64RTFToPlainText(normalized.content))
    }

    func testNormalizeWriteInputDecodesCanonicalContent() {
        let canonical = NotesRichTextCodec.encodePlainTextToBase64RTF("Stored body")

        let normalized = NotesRichTextCodec.normalizeWriteInput(content: canonical)

        XCTAssertEqual(normalized.content, canonical)
        XCTAssertEqual(normalized.plainText, "Stored body")
    }

    func testNormalizeWriteInputDerivesPlainTextFromEncodedSnapshot() {
        let normalized = NotesRichTextCodec.normalizeWriteInput(content: "Derived body")
        let decoded = NotesRichTextCodec.decodeBase64RTFToPlainText(normalized.content)

        XCTAssertEqual(normalized.plainText, decoded)
    }

    func testNotePayloadDecodesPlainTextFromResponse() throws {
        let encoded = NotesRichTextCodec.encodePlainTextToBase64RTF("Decoded body")
        let json = """
        {
          "id": "n1",
          "name": "Title.md",
          "content": "\(encoded)",
          "plain_text": "Decoded body",
          "content_format": "rtf",
          "path": "n1",
          "modified": 1,
          "created": 1
        }
        """

        let payload = try JSONDecoder().decode(
            NotePayload.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(payload.content, "Decoded body")
        XCTAssertEqual(payload.contentFormat, "rtf")
        XCTAssertFalse(payload.isCorrupt)
    }

    func testNotePayloadDropsRawFallbackWhenCanonicalDecodeFails() throws {
        let json = """
        {
          "id": "n2",
          "name": "Title.md",
          "content": "not-base64",
          "path": "n2",
          "modified": 1,
          "created": 1
        }
        """

        let payload = try JSONDecoder().decode(
            NotePayload.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(payload.content, "")
        XCTAssertTrue(payload.isCorrupt)
    }

    func testNotePayloadReadsLegacyContentFromMetadata() throws {
        let json = """
        {
          "id": "n3",
          "name": "Title.md",
          "content": "not-base64",
          "metadata": {
            "legacy_content": "legacy body"
          },
          "path": "n3",
          "modified": 1,
          "created": 1
        }
        """

        let payload = try JSONDecoder().decode(
            NotePayload.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(payload.legacyContent, "legacy body")
    }
}

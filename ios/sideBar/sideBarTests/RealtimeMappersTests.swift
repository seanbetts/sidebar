import XCTest
import sideBarShared
@testable import sideBar

final class RealtimeMappersTests: XCTestCase {
    func testMapNoteUsesTitleAndUpdatedAt() {
        let encoded = NotesRichTextCodec.encodePlainTextToBase64RTF("Body")
        let record = NoteRealtimeRecord(
            id: "n1",
            title: "Title",
            content: encoded,
            plainText: nil,
            contentFormat: nil,
            metadata: nil,
            updatedAt: "2024-01-01T12:00:00.000Z",
            deletedAt: nil
        )

        let mapped = RealtimeMappers.mapNote(record)

        XCTAssertEqual(mapped?.name, "Title")
        XCTAssertEqual(mapped?.path, "n1")
        XCTAssertEqual(mapped?.content, encoded)
        XCTAssertEqual(mapped?.plainText, "")
        XCTAssertNotNil(mapped?.modified)
    }

    func testMapNoteDropsRawFallbackWhenContentIsNotCanonical() {
        let record = NoteRealtimeRecord(
            id: "n3",
            title: "Title",
            content: "not-base64",
            plainText: nil,
            contentFormat: nil,
            metadata: nil,
            updatedAt: "2024-01-01T12:00:00.000Z",
            deletedAt: nil
        )

        let mapped = RealtimeMappers.mapNote(record)

        XCTAssertEqual(mapped?.content, "not-base64")
        XCTAssertEqual(mapped?.plainText, "")
    }

    func testMapNoteIgnoresMetadataFallbackFields() {
        let encoded = NotesRichTextCodec.encodePlainTextToBase64RTF("Rich text body")
        let record = NoteRealtimeRecord(
            id: "n2",
            title: "Title",
            content: encoded,
            plainText: nil,
            contentFormat: nil,
            metadata: [
                "plain_text": AnyCodable("Cached plain text"),
                "content_format": AnyCodable("rtf")
            ],
            updatedAt: "2024-01-01T12:00:00.000Z",
            deletedAt: nil
        )

        let mapped = RealtimeMappers.mapNote(record)

        XCTAssertEqual(mapped?.content, encoded)
        XCTAssertEqual(mapped?.plainText, "")
    }

    func testMapNotePrefersTopLevelPlainText() {
        let encoded = NotesRichTextCodec.encodePlainTextToBase64RTF("Rich text body")
        let record = NoteRealtimeRecord(
            id: "n4",
            title: "Title",
            content: encoded,
            plainText: "Top level plain text",
            contentFormat: "rtf",
            metadata: [
                "plain_text": AnyCodable("Metadata plain text"),
                "content_format": AnyCodable("markdown")
            ],
            updatedAt: "2024-01-01T12:00:00.000Z",
            deletedAt: nil
        )

        let mapped = RealtimeMappers.mapNote(record)

        XCTAssertEqual(mapped?.content, encoded)
        XCTAssertEqual(mapped?.plainText, "Top level plain text")
    }

    func testMapWebsiteUsesMetadataFlags() {
        let record = WebsiteRealtimeRecord(
            id: "w1",
            title: "Site",
            url: "https://example.com",
            domain: "example.com",
            metadata: [
                "pinned": AnyCodable(true),
                "pinned_order": AnyCodable(3),
                "archived": AnyCodable(true),
                "reading_time": AnyCodable("12 mins")
            ],
            savedAt: nil,
            publishedAt: nil,
            readingTime: nil,
            updatedAt: nil,
            lastOpenedAt: nil,
            deletedAt: nil
        )

        let mapped = RealtimeMappers.mapWebsite(record)

        XCTAssertEqual(mapped?.pinned, true)
        XCTAssertEqual(mapped?.pinnedOrder, 3)
        XCTAssertEqual(mapped?.archived, true)
        XCTAssertEqual(mapped?.readingTime, "12 mins")
    }

    func testMapIngestedFileUsesUpdatedAtWhenCreatedAtMissing() {
        let record = IngestedFileRealtimeRecord(
            id: "f1",
            filenameOriginal: "doc.txt",
            path: nil,
            mimeOriginal: "text/plain",
            sizeBytes: 12,
            sha256: nil,
            sourceUrl: nil,
            sourceMetadata: nil,
            pinned: nil,
            pinnedOrder: nil,
            createdAt: nil,
            updatedAt: "2024-01-01T12:00:00Z",
            deletedAt: nil
        )

        let mapped = RealtimeMappers.mapIngestedFile(record)

        XCTAssertEqual(mapped?.createdAt, "2024-01-01T12:00:00Z")
        XCTAssertEqual(mapped?.filenameOriginal, "doc.txt")
    }

    func testMapFileJobDefaultsAttempts() {
        let record = FileJobRealtimeRecord(
            fileId: "f1",
            status: "processing",
            stage: "parse",
            errorCode: nil,
            errorMessage: nil,
            attempts: nil,
            updatedAt: nil
        )

        let mapped = RealtimeMappers.mapFileJob(record)

        XCTAssertEqual(mapped.attempts, 0)
        XCTAssertEqual(mapped.status, "processing")
    }
}

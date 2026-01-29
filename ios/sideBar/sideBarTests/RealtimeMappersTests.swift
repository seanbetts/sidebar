import XCTest
import sideBarShared
@testable import sideBar

final class RealtimeMappersTests: XCTestCase {
    func testMapNoteUsesTitleAndUpdatedAt() {
        let record = NoteRealtimeRecord(
            id: "n1",
            title: "Title",
            content: "Body",
            metadata: nil,
            updatedAt: "2024-01-01T12:00:00.000Z",
            deletedAt: nil
        )

        let mapped = RealtimeMappers.mapNote(record)

        XCTAssertEqual(mapped?.name, "Title.md")
        XCTAssertEqual(mapped?.path, "n1")
        XCTAssertEqual(mapped?.content, "Body")
        XCTAssertNotNil(mapped?.modified)
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
                "archived": AnyCodable(true)
            ],
            savedAt: nil,
            publishedAt: nil,
            updatedAt: nil,
            lastOpenedAt: nil,
            deletedAt: nil
        )

        let mapped = RealtimeMappers.mapWebsite(record)

        XCTAssertEqual(mapped?.pinned, true)
        XCTAssertEqual(mapped?.pinnedOrder, 3)
        XCTAssertEqual(mapped?.archived, true)
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

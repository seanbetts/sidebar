import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class RealtimeMappersTests: XCTestCase {
    func testMapNoteUsesTitleAndUpdatedAt() {
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([.init(text: "Body", marks: [.bold])])
            ]
        )
        let record = try? JSONDecoder().decode(
            NoteRealtimeRecord.self,
            from: Data(
                """
                {
                  "id": "n1",
                  "title": "Title",
                  "document": {
                    "version": 1,
                    "blocks": [
                      {
                        "type": "paragraph",
                        "content": [
                          { "text": "Body", "marks": ["bold"] }
                        ]
                      }
                    ]
                  },
                  "document_version": 7,
                  "plain_text": "Body",
                  "metadata": null,
                  "updated_at": "2024-01-01T12:00:00.000Z",
                  "deleted_at": null
                }
                """.utf8
            )
        )

        let mapped = record.flatMap(RealtimeMappers.mapNote)

        XCTAssertEqual(mapped?.name, "Title")
        XCTAssertEqual(mapped?.path, "n1")
        XCTAssertEqual(mapped?.content, "Body")
        XCTAssertEqual(mapped?.plainText, "Body")
        XCTAssertEqual(mapped?.document, document)
        XCTAssertEqual(mapped?.documentVersion, 7)
        XCTAssertNotNil(mapped?.modified)
    }

    func testMapNoteFallsBackToPlainTextWhenSemanticDocumentMissing() {
        let record = try? JSONDecoder().decode(
            NoteRealtimeRecord.self,
            from: Data(
                """
                {
                  "id": "n4",
                  "title": "Title",
                  "plain_text": "Top level plain text",
                  "updated_at": "2024-01-01T12:00:00.000Z"
                }
                """.utf8
            )
        )

        let mapped = record.flatMap(RealtimeMappers.mapNote)

        XCTAssertEqual(mapped?.content, "Top level plain text")
        XCTAssertEqual(mapped?.plainText, "Top level plain text")
        XCTAssertEqual(
            mapped?.document,
            NotesSemanticDocument(
                blocks: [.paragraph([.init(text: "Top level plain text", marks: [])])]
            )
        )
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

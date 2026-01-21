import XCTest
@testable import sideBar

@MainActor
final class SupabaseRealtimeAdapterTests: XCTestCase {
    func testHandleNoteInsertDispatchesPayload() async {
        let expectation = expectation(description: "note insert")
        let handler = RecordingRealtimeHandler(noteExpectation: expectation)
        let adapter = SupabaseRealtimeAdapter(config: .fallbackForTesting(), handler: handler)
        let record = NoteRealtimeRecord(
            id: "n1",
            title: "Title",
            content: "Body",
            metadata: nil,
            updatedAt: nil,
            deletedAt: nil
        )

        adapter.handleNoteInsert(MockAction(record: record))

        await fulfillment(of: [expectation], timeout: 1.0)
        let payload = handler.notePayload
        XCTAssertEqual(payload?.eventType, .insert)
        XCTAssertEqual(payload?.table, RealtimeTable.notes)
        XCTAssertEqual(payload?.record?.id, "n1")
        XCTAssertNil(payload?.oldRecord)
    }

    func testHandleWebsiteUpdateIncludesOldRecord() async {
        let expectation = expectation(description: "website update")
        let handler = RecordingRealtimeHandler(websiteExpectation: expectation)
        let adapter = SupabaseRealtimeAdapter(config: .fallbackForTesting(), handler: handler)
        let record = WebsiteRealtimeRecord(
            id: "w1",
            title: "New",
            url: "https://example.com",
            domain: "example.com",
            metadata: nil,
            savedAt: nil,
            publishedAt: nil,
            updatedAt: nil,
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let old = WebsiteRealtimeRecord(
            id: "w1",
            title: "Old",
            url: "https://example.com",
            domain: "example.com",
            metadata: nil,
            savedAt: nil,
            publishedAt: nil,
            updatedAt: nil,
            lastOpenedAt: nil,
            deletedAt: nil
        )

        adapter.handleWebsiteUpdate(MockAction(record: record, oldRecord: old))

        await fulfillment(of: [expectation], timeout: 1.0)
        let payload = handler.websitePayload
        XCTAssertEqual(payload?.eventType, .update)
        XCTAssertEqual(payload?.record?.title, "New")
        XCTAssertEqual(payload?.oldRecord?.title, "Old")
    }

    func testHandleFileJobDeleteUsesOldRecord() async {
        let expectation = expectation(description: "file job delete")
        let handler = RecordingRealtimeHandler(fileJobExpectation: expectation)
        let adapter = SupabaseRealtimeAdapter(config: .fallbackForTesting(), handler: handler)
        let old = FileJobRealtimeRecord(
            fileId: "f1",
            status: "failed",
            stage: "extract",
            errorCode: "E",
            errorMessage: "Nope",
            attempts: 1,
            updatedAt: nil
        )

        adapter.handleFileJobDelete(MockAction(oldRecord: old))

        await fulfillment(of: [expectation], timeout: 1.0)
        let payload = handler.fileJobPayload
        XCTAssertEqual(payload?.eventType, .delete)
        XCTAssertEqual(payload?.oldRecord?.fileId, "f1")
    }
}

private final class RecordingRealtimeHandler: RealtimeEventHandler {
    var notePayload: RealtimePayload<NoteRealtimeRecord>? = nil
    var websitePayload: RealtimePayload<WebsiteRealtimeRecord>? = nil
    var ingestedPayload: RealtimePayload<IngestedFileRealtimeRecord>? = nil
    var fileJobPayload: RealtimePayload<FileJobRealtimeRecord>? = nil
    private let noteExpectation: XCTestExpectation?
    private let websiteExpectation: XCTestExpectation?
    private let ingestedExpectation: XCTestExpectation?
    private let fileJobExpectation: XCTestExpectation?

    init(
        noteExpectation: XCTestExpectation? = nil,
        websiteExpectation: XCTestExpectation? = nil,
        ingestedExpectation: XCTestExpectation? = nil,
        fileJobExpectation: XCTestExpectation? = nil
    ) {
        self.noteExpectation = noteExpectation
        self.websiteExpectation = websiteExpectation
        self.ingestedExpectation = ingestedExpectation
        self.fileJobExpectation = fileJobExpectation
    }

    func handleNoteEvent(_ payload: RealtimePayload<NoteRealtimeRecord>) {
        notePayload = payload
        noteExpectation?.fulfill()
    }

    func handleWebsiteEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) {
        websitePayload = payload
        websiteExpectation?.fulfill()
    }

    func handleIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>) {
        ingestedPayload = payload
        ingestedExpectation?.fulfill()
    }

    func handleFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) {
        fileJobPayload = payload
        fileJobExpectation?.fulfill()
    }
}

private struct MockAction: RealtimeActionDecoding {
    let record: Any?
    let oldRecord: Any?

    init(record: Any? = nil, oldRecord: Any? = nil) {
        self.record = record
        self.oldRecord = oldRecord
    }

    func decodeRecord<T: Decodable>(decoder: JSONDecoder) throws -> T {
        _ = decoder
        guard let record = record as? T else {
            throw RealtimeActionDecodingError.missingRecord
        }
        return record
    }

    func decodeOldRecord<T: Decodable>(decoder: JSONDecoder) throws -> T {
        _ = decoder
        guard let oldRecord = oldRecord as? T else {
            throw RealtimeActionDecodingError.missingOldRecord
        }
        return oldRecord
    }
}

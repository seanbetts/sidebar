import XCTest
import sideBarShared
import Realtime
import Supabase
@testable import sideBar

@MainActor
final class SupabaseRealtimeAdapterTests: XCTestCase {
    private static var retainedAdapters: [SupabaseRealtimeAdapter] = []
    private static var retainedHandlers: [RecordingRealtimeHandler] = []

    func testHandleNoteInsertDispatchesPayload() async {
        let expectation = expectation(description: "note insert")
        let handler = RecordingRealtimeHandler(noteExpectation: expectation)
        let adapter = retain(
            SupabaseRealtimeAdapter(config: .fallbackForTesting(), handler: handler),
            handler: handler
        )
        let record = NoteRealtimeRecord(
            id: "n1",
            title: "Title",
            document: nil,
            documentVersion: nil,
            plainText: "Body",
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
        let adapter = retain(
            SupabaseRealtimeAdapter(config: .fallbackForTesting(), handler: handler),
            handler: handler
        )
        let record = WebsiteRealtimeRecord(
            id: "w1",
            title: "New",
            url: "https://example.com",
            domain: "example.com",
            metadata: nil,
            savedAt: nil,
            publishedAt: nil,
            readingTime: nil,
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
            readingTime: nil,
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
        let adapter = retain(
            SupabaseRealtimeAdapter(config: .fallbackForTesting(), handler: handler),
            handler: handler
        )
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

    func testHandleTaskUpdateIncludesOldRecord() async {
        let expectation = expectation(description: "task update")
        let handler = RecordingRealtimeHandler(taskExpectation: expectation)
        let adapter = retain(
            SupabaseRealtimeAdapter(config: .fallbackForTesting(), handler: handler),
            handler: handler
        )
        let record = TaskRealtimeRecord(
            id: "t1",
            title: "New title",
            status: "today",
            deadline: "2026-02-18",
            notes: "new",
            projectId: "p1",
            groupId: "g1",
            repeating: false,
            repeatTemplate: false,
            recurrenceRule: nil,
            nextInstanceDate: nil,
            updatedAt: "new-updated",
            deletedAt: nil
        )
        let old = TaskRealtimeRecord(
            id: "t1",
            title: "Old title",
            status: "today",
            deadline: "2026-02-17",
            notes: "old",
            projectId: "p1",
            groupId: "g1",
            repeating: false,
            repeatTemplate: false,
            recurrenceRule: nil,
            nextInstanceDate: nil,
            updatedAt: "old-updated",
            deletedAt: nil
        )

        adapter.handleTaskUpdate(MockAction(record: record, oldRecord: old))

        await fulfillment(of: [expectation], timeout: 1.0)
        let payload = handler.taskPayload
        XCTAssertEqual(payload?.eventType, .update)
        XCTAssertEqual(payload?.table, RealtimeTable.tasks)
        XCTAssertEqual(payload?.record?.title, "New title")
        XCTAssertEqual(payload?.oldRecord?.title, "Old title")
    }

    func testHandleNoteInsertDeliversOnCurrentMainActorTurn() {
        let handler = RecordingRealtimeHandler()
        let adapter = retain(
            SupabaseRealtimeAdapter(config: .fallbackForTesting(), handler: handler),
            handler: handler
        )
        let record = NoteRealtimeRecord(
            id: "n-sync",
            title: "Title",
            document: nil,
            documentVersion: nil,
            plainText: "Body",
            metadata: nil,
            updatedAt: nil,
            deletedAt: nil
        )

        adapter.handleNoteInsert(MockAction(record: record))

        XCTAssertEqual(handler.notePayload?.record?.id, "n-sync")
    }

    func testEnqueueTransitionRunsOperationsSeriallyInSubmissionOrder() async {
        let adapter = retain(SupabaseRealtimeAdapter(config: .fallbackForTesting()))
        let executionOrder = SynchronizedIntArray()
        let operationCount = 8
        let gate = RealtimeTransitionGate()

        for index in 0..<operationCount {
            _ = adapter.enqueueTransition {
                await gate.waitUntilOpen()
                executionOrder.append(index)
            }
        }

        await gate.open()
        await adapter.transitionTask?.value
        XCTAssertEqual(executionOrder.values(), Array(0..<operationCount))
    }

    func testStopInternalClearsChannelsAfterRapidStateChurn() async {
        let adapter = retain(SupabaseRealtimeAdapter(config: .fallbackForTesting()))

        for index in 0..<10 {
            adapter.currentUserId = "user-\(index)"
            adapter.notesChannel = adapter.client.realtimeV2.channel("public:notes-\(index)")
            adapter.websitesChannel = adapter.client.realtimeV2.channel("public:websites-\(index)")
            adapter.ingestedFilesChannel = adapter.client.realtimeV2.channel("public:files-\(index)")
            adapter.fileJobsChannel = adapter.client.realtimeV2.channel("public:file-jobs-\(index)")
            adapter.tasksChannel = adapter.client.realtimeV2.channel("public:tasks-\(index)")
            adapter.taskProjectsChannel = adapter.client.realtimeV2.channel("public:task-projects-\(index)")
            adapter.taskGroupsChannel = adapter.client.realtimeV2.channel("public:task-groups-\(index)")
            await adapter.stopInternal()
            XCTAssertNil(adapter.notesChannel)
            XCTAssertNil(adapter.websitesChannel)
            XCTAssertNil(adapter.ingestedFilesChannel)
            XCTAssertNil(adapter.fileJobsChannel)
            XCTAssertNil(adapter.tasksChannel)
            XCTAssertNil(adapter.taskProjectsChannel)
            XCTAssertNil(adapter.taskGroupsChannel)
            XCTAssertNil(adapter.currentUserId)
            XCTAssertTrue(adapter.notesSubscriptions.isEmpty)
            XCTAssertTrue(adapter.websitesSubscriptions.isEmpty)
            XCTAssertTrue(adapter.ingestedFilesSubscriptions.isEmpty)
            XCTAssertTrue(adapter.fileJobsSubscriptions.isEmpty)
            XCTAssertTrue(adapter.tasksSubscriptions.isEmpty)
            XCTAssertTrue(adapter.taskProjectsSubscriptions.isEmpty)
            XCTAssertTrue(adapter.taskGroupsSubscriptions.isEmpty)
        }
    }

    func testSubscribeToFileJobsScopesCallbacksToCurrentUser() async {
        let adapter = retain(SupabaseRealtimeAdapter(config: .fallbackForTesting()))

        XCTAssertEqual(adapter.fileJobsFilter(userId: "user-123"), "user_id=eq.user-123")
    }

    private func retain(_ adapter: SupabaseRealtimeAdapter) -> SupabaseRealtimeAdapter {
        Self.retainedAdapters.append(adapter)
        return adapter
    }

    private func retain(
        _ adapter: SupabaseRealtimeAdapter,
        handler: RecordingRealtimeHandler
    ) -> SupabaseRealtimeAdapter {
        Self.retainedAdapters.append(adapter)
        Self.retainedHandlers.append(handler)
        return adapter
    }
}

private final class RecordingRealtimeHandler: RealtimeEventHandler {
    var notePayload: RealtimePayload<NoteRealtimeRecord>?
    var websitePayload: RealtimePayload<WebsiteRealtimeRecord>?
    var ingestedPayload: RealtimePayload<IngestedFileRealtimeRecord>?
    var fileJobPayload: RealtimePayload<FileJobRealtimeRecord>?
    var taskPayload: RealtimePayload<TaskRealtimeRecord>?
    var taskProjectPayload: RealtimePayload<TaskProjectRealtimeRecord>?
    var taskGroupPayload: RealtimePayload<TaskGroupRealtimeRecord>?
    private let noteExpectation: XCTestExpectation?
    private let websiteExpectation: XCTestExpectation?
    private let ingestedExpectation: XCTestExpectation?
    private let fileJobExpectation: XCTestExpectation?
    private let taskExpectation: XCTestExpectation?
    private let taskProjectExpectation: XCTestExpectation?
    private let taskGroupExpectation: XCTestExpectation?

    init(
        noteExpectation: XCTestExpectation? = nil,
        websiteExpectation: XCTestExpectation? = nil,
        ingestedExpectation: XCTestExpectation? = nil,
        fileJobExpectation: XCTestExpectation? = nil,
        taskExpectation: XCTestExpectation? = nil,
        taskProjectExpectation: XCTestExpectation? = nil,
        taskGroupExpectation: XCTestExpectation? = nil
    ) {
        self.noteExpectation = noteExpectation
        self.websiteExpectation = websiteExpectation
        self.ingestedExpectation = ingestedExpectation
        self.fileJobExpectation = fileJobExpectation
        self.taskExpectation = taskExpectation
        self.taskProjectExpectation = taskProjectExpectation
        self.taskGroupExpectation = taskGroupExpectation
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

    func handleTaskEvent(_ payload: RealtimePayload<TaskRealtimeRecord>) {
        taskPayload = payload
        taskExpectation?.fulfill()
    }

    func handleTaskProjectEvent(_ payload: RealtimePayload<TaskProjectRealtimeRecord>) {
        taskProjectPayload = payload
        taskProjectExpectation?.fulfill()
    }

    func handleTaskGroupEvent(_ payload: RealtimePayload<TaskGroupRealtimeRecord>) {
        taskGroupPayload = payload
        taskGroupExpectation?.fulfill()
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

private actor RealtimeTransitionGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilOpen() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private final class SynchronizedIntArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    func append(_ value: Int) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    func values() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

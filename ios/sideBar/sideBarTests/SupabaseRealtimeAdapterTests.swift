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
            adapter.currentAccessToken = "token-\(index)"
            for domain in RealtimeSubscriptionDomain.allCases {
                adapter.setChannel(adapter.client.realtimeV2.channel("public:\(domain.table)-\(index)"), for: domain)
            }
            adapter.updateRealtimeConnectionState()
            XCTAssertTrue(adapter.isRealtimeConnected)
            await adapter.stopInternal()
            XCTAssertNil(adapter.currentUserId)
            XCTAssertNil(adapter.currentAccessToken)
            for domain in RealtimeSubscriptionDomain.allCases {
                XCTAssertNil(adapter.channel(for: domain))
                XCTAssertTrue(adapter.subscriptions(for: domain).isEmpty)
            }
            XCTAssertFalse(adapter.isRealtimeConnected)
        }
    }

    func testRealtimeConnectionHealthRequiresAllDomainsAndClearsFailures() {
        let adapter = retain(SupabaseRealtimeAdapter(config: .fallbackForTesting()))
        adapter.currentUserId = "user-1"
        adapter.currentAccessToken = "token"
        for domain in RealtimeSubscriptionDomain.allCases where domain != .taskGroups {
            adapter.setChannel(adapter.client.realtimeV2.channel("public:\(domain.table)"), for: domain)
        }
        adapter.updateRealtimeConnectionState()
        XCTAssertFalse(adapter.isRealtimeConnected)

        adapter.setChannel(adapter.client.realtimeV2.channel("public:task_groups"), for: .taskGroups)
        adapter.updateRealtimeConnectionState()
        XCTAssertTrue(adapter.isRealtimeConnected)

        adapter.markRealtimeSubscriptionFailed(for: .websites)
        XCTAssertNil(adapter.channel(for: .websites))
        XCTAssertFalse(adapter.isRealtimeConnected)
    }

    func testSubscribeToFileJobsScopesCallbacksToCurrentUser() async {
        let adapter = retain(SupabaseRealtimeAdapter(config: .fallbackForTesting()))

        XCTAssertEqual(adapter.fileJobsFilter(userId: "user-123"), "user_id=eq.user-123")
    }

    func testSubscriptionSessionRequiresUserIdAndAccessToken() {
        XCTAssertNil(RealtimeSubscriptionSession(userId: nil, accessToken: "token"))
        XCTAssertNil(RealtimeSubscriptionSession(userId: "user-1", accessToken: nil))
        XCTAssertNil(RealtimeSubscriptionSession(userId: "   ", accessToken: "token"))
        XCTAssertNil(RealtimeSubscriptionSession(userId: "user-1", accessToken: ""))

        let session = RealtimeSubscriptionSession(userId: " user-1 ", accessToken: "token")

        XCTAssertEqual(session?.userId, "user-1")
        XCTAssertEqual(session?.accessToken, "token")
    }

    func testSubscriptionPlanCentralizesRealtimeDomainOrdering() {
        let currentSession = RealtimeSubscriptionSession(userId: "user-1", accessToken: "token")
        let nextSession = RealtimeSubscriptionSession(userId: "user-1", accessToken: "token")!
        let allExistingPlan = SupabaseRealtimeAdapter.makeSubscriptionPlan(
            currentSession: currentSession,
            nextSession: nextSession
        ) { _ in true }
        XCTAssertTrue(allExistingPlan.domains.isEmpty)

        let missingChannelPlan = SupabaseRealtimeAdapter.makeSubscriptionPlan(
            currentSession: currentSession,
            nextSession: nextSession
        ) { domain in
            domain != .websites && domain != .taskGroups
        }
        XCTAssertEqual(missingChannelPlan.domains, [.websites, .taskGroups])

        let tokenChangedPlan = SupabaseRealtimeAdapter.makeSubscriptionPlan(
            currentSession: RealtimeSubscriptionSession(userId: "user-1", accessToken: "old-token"),
            nextSession: RealtimeSubscriptionSession(userId: "user-1", accessToken: "new-token")!
        ) { _ in true }
        XCTAssertEqual(tokenChangedPlan.domains, RealtimeSubscriptionDomain.allCases)
    }

    func testTokenChangeRequiresRealtimeResubscribeForExistingChannels() {
        XCTAssertTrue(
            SupabaseRealtimeAdapter.shouldResubscribeChannel(
                currentSession: RealtimeSubscriptionSession(userId: "user-1", accessToken: "old-token"),
                nextSession: RealtimeSubscriptionSession(userId: "user-1", accessToken: "new-token")!,
                hasChannel: true
            )
        )
        XCTAssertFalse(
            SupabaseRealtimeAdapter.shouldResubscribeChannel(
                currentSession: RealtimeSubscriptionSession(userId: "user-1", accessToken: "token"),
                nextSession: RealtimeSubscriptionSession(userId: "user-1", accessToken: "token")!,
                hasChannel: true
            )
        )
    }

    func testRealtimeAdapterStoresChannelsAndSubscriptionsInDomainSlots() throws {
        let normalized = try realtimeSource(named: "SupabaseRealtimeAdapter.swift")
            .normalizedForRealtimeSourceAssertions()

        XCTAssertTrue(normalized.contains("varsubscriptionSlots:[RealtimeSubscriptionDomain:RealtimeSubscriptionSlot]="))
        XCTAssertFalse(normalized.contains("varnotesChannel:RealtimeChannelV2?"))
        XCTAssertFalse(normalized.contains("varwebsitesChannel:RealtimeChannelV2?"))
        XCTAssertFalse(normalized.contains("varingestedFilesChannel:RealtimeChannelV2?"))
        XCTAssertFalse(normalized.contains("varfileJobsChannel:RealtimeChannelV2?"))
        XCTAssertFalse(normalized.contains("vartasksChannel:RealtimeChannelV2?"))
        XCTAssertFalse(normalized.contains("vartaskProjectsChannel:RealtimeChannelV2?"))
        XCTAssertFalse(normalized.contains("vartaskGroupsChannel:RealtimeChannelV2?"))
        XCTAssertFalse(normalized.contains("varnotesSubscriptions:[ObservationToken]"))
        XCTAssertFalse(normalized.contains("varwebsitesSubscriptions:[ObservationToken]"))
        XCTAssertFalse(normalized.contains("varingestedFilesSubscriptions:[ObservationToken]"))
        XCTAssertFalse(normalized.contains("varfileJobsSubscriptions:[ObservationToken]"))
        XCTAssertFalse(normalized.contains("vartasksSubscriptions:[ObservationToken]"))
        XCTAssertFalse(normalized.contains("vartaskProjectsSubscriptions:[ObservationToken]"))
        XCTAssertFalse(normalized.contains("vartaskGroupsSubscriptions:[ObservationToken]"))
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

    private func realtimeSource(
        named fileName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sourceURL = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Services")
            .appendingPathComponent("Realtime")
            .appendingPathComponent(fileName)

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(fileName): \(error)", file: file, line: line)
            throw error
        }
    }
}

private extension String {
    func normalizedForRealtimeSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
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

import Foundation
import sideBarShared
import XCTest

final class WidgetDataBridgeTests: XCTestCase {
    private func makeBridge(
        userDefaults: UserDefaults,
        diagnostics: @escaping (String, String, [String: String]) -> Void = { _, _, _ in },
        reloader: @escaping (WidgetContentType) -> Void = { _ in }
    ) -> WidgetDataBridge {
        let lockFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetDataBridgeTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("pending-operations.lock", isDirectory: false)
        let pendingOperationStore = WidgetPendingOperationStore(
            userDefaultsProvider: { userDefaults },
            lockFileURLProvider: { lockFileURL }
        )
        return WidgetDataBridge(
            userDefaultsProvider: { userDefaults },
            appGroupResolutionProvider: {
                WidgetBridgeAppGroupResolution(id: "group.test.widget", source: "test")
            },
            diagnosticsRecorder: diagnostics,
            timelineReloader: reloader,
            pendingOperationStore: pendingOperationStore
        )
    }

    func testStoreAndLoadRoundTripPreservesWidgetPayload() {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)
        let payload = WidgetNoteData(
            notes: [WidgetNote(id: "/note.md", name: "Note", path: "/note.md", pinned: true, pinnedOrder: 0)],
            totalCount: 1
        )

        bridge.store(payload, for: .notes)
        let loaded: WidgetNoteData = bridge.load(for: .notes)

        XCTAssertEqual(loaded.totalCount, 1)
        XCTAssertEqual(loaded.notes.map(\.path), ["/note.md"])
    }

    func testPendingOperationsRoundTripAndDeduplicate() {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)
        let operation = WidgetPendingOperation(itemId: "task-1", action: TaskWidgetAction.complete)

        bridge.recordPendingOperation(operation, for: .tasks)
        bridge.recordPendingOperation(operation, for: .tasks)
        let pending = bridge.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.itemId, "task-1")
        XCTAssertEqual(pending.first?.action, .complete)
        XCTAssertTrue(
            bridge.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self).isEmpty
        )
    }

    func testConcurrentPendingOperationRecordsPreserveEveryUniqueOperation() async {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    let operation = WidgetPendingOperation(
                        itemId: "task-\(index)",
                        action: TaskWidgetAction.complete
                    )
                    bridge.recordPendingOperation(operation, for: .tasks)
                }
            }
        }

        let pending = bridge.loadPendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        XCTAssertEqual(Set(pending.map(\.itemId)).count, 50)
    }

    func testConcurrentDuplicatePendingOperationRecordsDeduplicate() async {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)
        let operation = WidgetPendingOperation(itemId: "task-1", action: TaskWidgetAction.complete)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    bridge.recordPendingOperation(operation, for: .tasks)
                }
            }
        }

        let pending = bridge.loadPendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.itemId, "task-1")
        XCTAssertEqual(pending.first?.action, .complete)
    }

    func testPendingOperationStoreWaitsForExternalProcessFileLock() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WidgetPendingOperationStoreExternalLockTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let lockFileURL = temporaryDirectory.appendingPathComponent("pending-operations.lock")
        let suiteName = "WidgetDataBridgeTests.external-lock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let helperReady = expectation(description: "External helper acquired lock")
        let helperExited = DispatchSemaphore(value: 0)
        let helperResources = makeExternalLockHelper(
            lockFileURL: lockFileURL,
            readyExpectation: helperReady,
            exitedSemaphore: helperExited
        )
        let helper = helperResources.process
        let helperOutput = helperResources.output
        let helperInput = helperResources.input
        defer {
            helperOutput.fileHandleForReading.readabilityHandler = nil
            try? helperInput.fileHandleForWriting.close()
            if helper.isRunning {
                helper.terminate()
            }
        }

        try helper.run()
        guard XCTWaiter.wait(for: [helperReady], timeout: 2) == .completed else {
            XCTFail("External lock helper did not become ready")
            return
        }

        let enteredCriticalSection = DispatchSemaphore(value: 0)
        let operationCompleted = DispatchSemaphore(value: 0)
        let operationStarted = DispatchSemaphore(value: 0)
        let store = WidgetPendingOperationStore(
            userDefaultsProvider: {
                enteredCriticalSection.signal()
                return defaults
            },
            lockFileURLProvider: { lockFileURL }
        )
        let operationThread = Thread {
            operationStarted.signal()
            _ = store.record(
                WidgetPendingOperation(
                    itemId: "external-lock-task",
                    action: TaskWidgetAction.complete
                ),
                key: WidgetContentType.tasks.pendingKey
            )
            operationCompleted.signal()
        }
        operationThread.name = "WidgetPendingOperationStoreExternalLockTest"
        operationThread.qualityOfService = .userInteractive
        operationThread.start()

        XCTAssertEqual(operationStarted.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(
            enteredCriticalSection.wait(timeout: .now() + 0.25),
            .timedOut,
            "The test process entered shared storage while another process held the file lock"
        )

        helperInput.fileHandleForWriting.write(Data([0]))
        try helperInput.fileHandleForWriting.close()
        XCTAssertEqual(enteredCriticalSection.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(operationCompleted.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(helperExited.wait(timeout: .now() + 2), .success)

        let pending: [WidgetPendingOperation<TaskWidgetAction>] = store.load(
            key: WidgetContentType.tasks.pendingKey,
            actionType: TaskWidgetAction.self
        )
        XCTAssertEqual(pending.map(\.itemId), ["external-lock-task"])
    }

    private func makeExternalLockHelper(
        lockFileURL: URL,
        readyExpectation: XCTestExpectation,
        exitedSemaphore: DispatchSemaphore
    ) -> ExternalLockHelperResources {
        let process = Process()
        let output = Pipe()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import fcntl
            import os
            import sys
            lock_path = sys.argv[1]
            os.makedirs(os.path.dirname(lock_path), exist_ok=True)
            with open(lock_path, "a+") as lock_file:
                fcntl.flock(lock_file, fcntl.LOCK_EX)
                print("LOCKED", flush=True)
                sys.stdin.buffer.read(1)
                fcntl.flock(lock_file, fcntl.LOCK_UN)
            """,
            lockFileURL.path
        ]
        process.standardOutput = output
        process.standardError = output
        process.standardInput = input
        process.terminationHandler = { _ in exitedSemaphore.signal() }
        output.fileHandleForReading.readabilityHandler = { handle in
            guard let message = String(data: handle.availableData, encoding: .utf8),
                  message.contains("LOCKED") else {
                return
            }
            handle.readabilityHandler = nil
            readyExpectation.fulfill()
        }
        return ExternalLockHelperResources(
            process: process,
            output: output,
            input: input
        )
    }

    func testConcurrentPendingOperationRecordsAndRemovesPreserveExpectedOperations() async {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)
        let removableOperations = (0..<50).map { index in
            WidgetPendingOperation(itemId: "remove-\(index)", action: TaskWidgetAction.complete)
        }

        for operation in removableOperations {
            bridge.recordPendingOperation(operation, for: .tasks)
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                let operationId = removableOperations[index].id
                group.addTask {
                    bridge.removePendingOperation(
                        withId: operationId,
                        for: .tasks,
                        actionType: TaskWidgetAction.self
                    )
                }
                group.addTask {
                    let operation = WidgetPendingOperation(
                        itemId: "record-\(index)",
                        action: TaskWidgetAction.complete
                    )
                    bridge.recordPendingOperation(operation, for: .tasks)
                }
            }
        }

        let pending = bridge.loadPendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        let itemIds = Set(pending.map(\.itemId))

        XCTAssertEqual(itemIds.count, 50)
        XCTAssertTrue(itemIds.isDisjoint(with: Set(removableOperations.map(\.itemId))))
        XCTAssertEqual(itemIds, Set((0..<50).map { "record-\($0)" }))
    }

    func testHasStoredSnapshotReturnsTrueAfterStoringEmptyPayload() {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)

        XCTAssertFalse(bridge.hasStoredSnapshot(for: .notes))

        bridge.store(WidgetNoteData.empty, for: .notes)

        XCTAssertTrue(bridge.hasStoredSnapshot(for: .notes))
    }

    func testLoadPendingOperationsDoesNotConsumeStoredOperations() {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)
        let completion = WidgetPendingOperation(itemId: "task-1", action: TaskWidgetAction.complete)

        bridge.recordPendingOperation(completion, for: .tasks)

        let loaded = bridge.loadPendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        let consumed = bridge.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, completion.id)
        XCTAssertEqual(consumed.count, 1)
        XCTAssertEqual(consumed.first?.id, completion.id)
    }

    func testRemovePendingOperationByIdentifierKeepsUnrelatedOperations() {
        let suiteName = "WidgetDataBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bridge = makeBridge(userDefaults: defaults)
        let completion = WidgetPendingOperation(itemId: "task-1", action: TaskWidgetAction.complete)
        let addNew = WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew)

        bridge.recordPendingOperation(completion, for: .tasks)
        bridge.recordPendingOperation(addNew, for: .tasks)
        bridge.removePendingOperation(
            withId: completion.id,
            for: .tasks,
            actionType: TaskWidgetAction.self
        )

        let remaining = bridge.loadPendingOperations(for: .tasks, actionType: TaskWidgetAction.self)

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, addNew.id)
        XCTAssertEqual(remaining.first?.action, .addNew)
    }
}

private struct ExternalLockHelperResources {
    let process: Process
    let output: Pipe
    let input: Pipe
}

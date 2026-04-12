import XCTest
@testable import sideBar

@MainActor
final class HeaderStatusControllerTests: XCTestCase {
    func testControllerShowsSyncThenIngestionWhenBothDomainsVisible() {
        let sleeper = HeaderStatusTestSleeper()
        let controller = HeaderStatusController(sleepFor: sleeper.sleep(for:))

        controller.applyIngestion(snapshot: .active(rows: [makeIngestionRow()]))
        controller.applySync(snapshot: .error(rows: [makeSyncErrorRow()]))

        XCTAssertEqual(controller.visiblePills.map(\.kind), [.sync, .ingestion])
        XCTAssertEqual(controller.visiblePills.first?.isActionable, true)
    }

    func testSyncSnapshotMapsToExpectedPillAcrossAllPriorityBranches() {
        let sleeper = HeaderStatusTestSleeper()
        let controller = HeaderStatusController(sleepFor: sleeper.sleep(for:))

        controller.applySync(snapshot: .error(rows: [makeSyncErrorRow()]))
        XCTAssertEqual(controller.visiblePills.first?.label, "Sync error")

        controller.applySync(snapshot: .syncing)
        XCTAssertEqual(controller.visiblePills.first?.label, "Syncing")

        controller.applySync(snapshot: .pending)
        XCTAssertEqual(controller.visiblePills.first?.label, "Pending")
    }

    func testInformationalReplacementSwapsImmediatelyWithoutWaitingForPriorExpiry() async {
        let sleeper = HeaderStatusTestSleeper()
        let controller = HeaderStatusController(sleepFor: sleeper.sleep(for:))

        controller.applyIngestion(
            snapshot: .success(
                messageID: "ready-1",
                title: "Ready",
                message: "Quarterly report is ready."
            )
        )
        await waitForPendingSleeps(1, on: sleeper)
        sleeper.advance(by: .seconds(4))
        await Task.yield()

        controller.applyIngestion(
            snapshot: .failureWithoutAction(
                messageID: "failed-1",
                title: "Upload failed",
                message: "This file can't be retried here."
            )
        )
        await waitForPendingSleeps(1, on: sleeper)

        XCTAssertEqual(controller.visiblePills.first?.id, "failed-1")
        XCTAssertEqual(controller.visiblePills.first?.expiresAfter, .seconds(5))
        XCTAssertEqual(controller.visiblePills.first?.tone, .error)
        XCTAssertEqual(controller.visiblePills.first?.accessibilityLabel, "Upload failed")
        XCTAssertNotNil(controller.visiblePills.first?.popover)

        sleeper.advance(by: .seconds(1))
        await Task.yield()
        XCTAssertEqual(controller.visiblePills.first?.id, "failed-1")

        sleeper.advance(by: .seconds(4))
        await assertEventually(controller.visiblePills.isEmpty, message: "Expected ingestion pill to expire")
    }

    func testInformationalPillExpiresAfterFiveSecondsWithoutAffectingOtherDomain() async {
        let sleeper = HeaderStatusTestSleeper()
        let controller = HeaderStatusController(sleepFor: sleeper.sleep(for:))

        controller.applySync(snapshot: .error(rows: [makeSyncErrorRow()]))
        controller.applyIngestion(
            snapshot: .success(
                messageID: "ready-1",
                title: "Ready",
                message: "Quarterly report is ready."
            )
        )
        await waitForPendingSleeps(1, on: sleeper)

        sleeper.advance(by: .seconds(5))
        await assertEventually(
            controller.visiblePills.map(\.kind) == [.sync],
            message: "Expected only the sync pill to remain"
        )
    }

    private func makeSyncErrorRow() -> HeaderStatusRowModel {
        HeaderStatusRowModel(
            id: "sync-1",
            title: "Delete website",
            detail: nil,
            actions: [
                .init(id: "retry", title: "Retry", role: .default),
                .init(id: "cancel", title: "Cancel", role: .destructive)
            ]
        )
    }

    private func makeIngestionRow() -> HeaderStatusRowModel {
        HeaderStatusRowModel(
            id: "file-1",
            title: "Quarterly report",
            detail: nil,
            actions: [.init(id: "cancel", title: "Cancel", role: .cancel)]
        )
    }

    private func waitForPendingSleeps(
        _ expectedCount: Int,
        on sleeper: HeaderStatusTestSleeper
    ) async {
        for _ in 0..<10 {
            if sleeper.pendingSleepCount() == expectedCount {
                return
            }

            await Task.yield()
        }

        XCTFail("Expected \(expectedCount) pending sleeps")
    }

    private func assertEventually(
        _ condition: @autoclosure @escaping () -> Bool,
        message: String
    ) async {
        for _ in 0..<20 {
            if condition() {
                return
            }

            await Task.yield()
        }

        XCTFail(message)
    }
}

private final class HeaderStatusTestSleeper: @unchecked Sendable {
    private struct PendingSleep {
        var remaining: Duration
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var pendingSleeps: [UUID: PendingSleep] = [:]

    func pendingSleepCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingSleeps.count
    }

    func sleep(for duration: Duration) async {
        let id = UUID()

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                pendingSleeps[id] = PendingSleep(remaining: duration, continuation: continuation)
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let continuation = pendingSleeps.removeValue(forKey: id)?.continuation
            lock.unlock()
            continuation?.resume()
        }
    }

    func advance(by duration: Duration) {
        var resumableContinuations: [CheckedContinuation<Void, Never>] = []

        lock.lock()
        var resumableIDs: [UUID] = []

        for id in Array(pendingSleeps.keys) {
            guard let pendingSleep = pendingSleeps[id] else { continue }
            let updatedRemaining = pendingSleep.remaining - duration

            if updatedRemaining <= .zero {
                resumableIDs.append(id)
            } else {
                pendingSleeps[id]?.remaining = updatedRemaining
            }
        }

        for id in resumableIDs {
            if let continuation = pendingSleeps.removeValue(forKey: id)?.continuation {
                resumableContinuations.append(continuation)
            }
        }
        lock.unlock()

        for continuation in resumableContinuations {
            continuation.resume()
        }
    }
}

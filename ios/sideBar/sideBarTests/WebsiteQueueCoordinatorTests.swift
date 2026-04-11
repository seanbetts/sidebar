import XCTest
@testable import sideBar

@MainActor
final class WebsiteQueueCoordinatorTests: XCTestCase {
    func testCoordinatorStartsReplayWhenWebsiteHandoffArrivesAndGatesPass() async {
        let state = WebsiteQueueCoordinatorHarness(
            hasPendingWork: true,
            hasBackgroundContinuationWork: true,
            canReplayNow: true
        )
        let coordinator = state.makeCoordinator()

        coordinator.queueDidChange(trigger: .handoff)

        await state.waitForReplayCount(1)
        XCTAssertEqual(state.scheduleCount, 1)
    }

    func testCoordinatorDefersReplayWhenSignedOutOrProtectedContentLocked() async {
        let state = WebsiteQueueCoordinatorHarness(
            hasPendingWork: true,
            hasBackgroundContinuationWork: true,
            canReplayNow: false
        )
        let coordinator = state.makeCoordinator()

        coordinator.queueDidChange(trigger: .handoff)

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(state.replayCount, 0)
        XCTAssertEqual(state.scheduleCount, 1)

        state.setCanReplayNow(true)
        coordinator.authDidBecomeRunnable()

        await state.waitForReplayCount(1)
    }

    func testCoordinatorReschedulesReplayWhenWorkRemains() async {
        let state = WebsiteQueueCoordinatorHarness(
            hasPendingWork: true,
            hasBackgroundContinuationWork: true,
            canReplayNow: true
        )
        let coordinator = state.makeCoordinator()

        coordinator.queueDidChange(trigger: .handoff)

        await state.waitForReplayCount(1)
        XCTAssertEqual(state.scheduleCount, 1)
    }

    func testCoordinatorIgnoresDuplicateStartRequestsWhileReplayIsInFlight() async {
        let gate = AsyncGate()
        let state = WebsiteQueueCoordinatorHarness(
            hasPendingWork: true,
            hasBackgroundContinuationWork: true,
            canReplayNow: true,
            onReplay: {
                await gate.wait()
            }
        )
        let coordinator = state.makeCoordinator()

        coordinator.queueDidChange(trigger: .handoff)
        coordinator.appDidBecomeActive()

        await state.waitForReplayCount(1)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(state.replayCount, 1)

        state.setHasPendingWork(false)
        state.setHasBackgroundContinuationWork(false)
        await gate.open()

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(state.replayCount, 1)
    }

    func testCoordinatorRetryWakeupStartsReplayWhenDeferredWorkBecomesRunnable() async {
        var state: WebsiteQueueCoordinatorHarness!
        state = WebsiteQueueCoordinatorHarness(
            hasPendingWork: true,
            hasBackgroundContinuationWork: true,
            canReplayNow: false,
            onReplay: {
                state.setHasPendingWork(false)
                state.setHasBackgroundContinuationWork(false)
            }
        )
        let coordinator = state.makeCoordinator(retryDelay: .milliseconds(10))

        coordinator.queueDidChange(trigger: .handoff)
        state.setCanReplayNow(true)

        await state.waitForReplayCount(1)
    }
}

@MainActor
private final class WebsiteQueueCoordinatorHarness {
    private var hasPendingWork: Bool
    private var hasBackgroundContinuationWork: Bool
    private var canReplayNow: Bool
    private let onReplay: (() async -> Void)?

    private(set) var replayCount = 0
    private(set) var scheduleCount = 0

    init(
        hasPendingWork: Bool,
        hasBackgroundContinuationWork: Bool,
        canReplayNow: Bool,
        onReplay: (() async -> Void)? = nil
    ) {
        self.hasPendingWork = hasPendingWork
        self.hasBackgroundContinuationWork = hasBackgroundContinuationWork
        self.canReplayNow = canReplayNow
        self.onReplay = onReplay
    }

    func makeCoordinator(retryDelay: Duration? = nil) -> WebsiteQueueCoordinator {
        WebsiteQueueCoordinator(
            hasPendingWork: { [weak self] in
                self?.hasPendingWork ?? false
            },
            hasBackgroundContinuationWork: { [weak self] in
                self?.hasBackgroundContinuationWork ?? false
            },
            canReplayNow: { [weak self] in
                self?.canReplayNow ?? false
            },
            replay: { [weak self] in
                guard let self else { return }
                self.recordReplay()
                await self.onReplay?()
            },
            scheduleContinuation: { [weak self] in
                self?.recordSchedule()
            },
            retryDelay: retryDelay
        )
    }

    func setHasPendingWork(_ value: Bool) {
        hasPendingWork = value
    }

    func setHasBackgroundContinuationWork(_ value: Bool) {
        hasBackgroundContinuationWork = value
    }

    func setCanReplayNow(_ value: Bool) {
        canReplayNow = value
    }

    func recordReplay() {
        replayCount += 1
    }

    func recordSchedule() {
        scheduleCount += 1
    }

    func waitForReplayCount(_ expected: Int, attempts: Int = 40) async {
        for _ in 0..<attempts where replayCount < expected {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(replayCount, expected)
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

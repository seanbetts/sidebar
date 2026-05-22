import XCTest
@testable import sideBar

@MainActor
final class AsyncJobProgressCoordinatorTests: XCTestCase {
    func testRegistersActiveJobAndStopsOnRealtimeTerminalState() async {
        let coordinator = AsyncJobProgressCoordinator()
        let descriptor = AsyncJobDescriptor(
            domain: .websiteSave,
            entityId: "pending:https://example.com",
            jobId: "job-1",
            terminalStatuses: ["completed", "failed", "canceled", "stalled"]
        )
        coordinator.register(descriptor)

        XCTAssertTrue(coordinator.hasActiveJob(jobId: "job-1"))

        let result = await coordinator.applyRealtimeStatus(
            jobId: "job-1",
            status: AsyncJobStatus(rawValue: "completed"),
            userMessage: nil
        )

        XCTAssertEqual(result, .terminal(status: "completed", userMessage: nil))
        XCTAssertFalse(coordinator.hasActiveJob(jobId: "job-1"))
    }

    func testFallbackPollingStartsOnlyWhenHealthAllowsIt() {
        let coordinator = AsyncJobProgressCoordinator()
        coordinator.register(
            AsyncJobDescriptor(
                domain: .fileProcessing,
                entityId: "file-1",
                jobId: "job-file-1",
                terminalStatuses: ["ready", "completed", "failed", "canceled"]
            )
        )

        XCTAssertFalse(coordinator.shouldPoll(jobId: "job-file-1", health: .healthy))
        XCTAssertTrue(coordinator.shouldPoll(jobId: "job-file-1", health: .degraded))
    }

    func testTerminalStatusNormalizationTrimsWhitespaceAndIgnoresCase() async {
        let coordinator = AsyncJobProgressCoordinator()
        coordinator.register(
            AsyncJobDescriptor(
                domain: .websiteTranscript,
                entityId: "transcript-1",
                jobId: "job-transcript-1",
                terminalStatuses: [" Completed "]
            )
        )

        let result = await coordinator.applyRealtimeStatus(
            jobId: "job-transcript-1",
            status: AsyncJobStatus(rawValue: " COMPLETED "),
            userMessage: nil
        )

        XCTAssertEqual(result, .terminal(status: "completed", userMessage: nil))
        XCTAssertFalse(coordinator.hasActiveJob(jobId: "job-transcript-1"))
    }
}

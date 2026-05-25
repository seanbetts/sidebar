import XCTest
@testable import sideBar

final class WriteQueueRetryPolicyTests: XCTestCase {
    func testRetryAttemptsStopAfterMaximumRetryCount() {
        XCTAssertTrue(WriteQueueRetryPolicy.shouldRetry(attempts: 1))
        XCTAssertTrue(WriteQueueRetryPolicy.shouldRetry(attempts: 4))
        XCTAssertFalse(WriteQueueRetryPolicy.shouldRetry(attempts: 5))
    }

    func testBackoffDelayDoublesAndCapsAtSixteenSeconds() {
        XCTAssertEqual(WriteQueueRetryPolicy.backoffDelayNanoseconds(forAttempt: 1), 1_000_000_000)
        XCTAssertEqual(WriteQueueRetryPolicy.backoffDelayNanoseconds(forAttempt: 2), 2_000_000_000)
        XCTAssertEqual(WriteQueueRetryPolicy.backoffDelayNanoseconds(forAttempt: 6), 16_000_000_000)
        XCTAssertEqual(WriteQueueRetryPolicy.backoffDelayNanoseconds(forAttempt: 12), 16_000_000_000)
    }

    func testReplayPolicyAllowsTransientHTTPFailuresOnly() {
        XCTAssertTrue(
            WriteQueueRetryPolicy.shouldReplayFailedWrite(
                lastError: "requestFailed(408)",
                conflictReason: nil
            )
        )
        XCTAssertTrue(
            WriteQueueRetryPolicy.shouldReplayFailedWrite(
                lastError: "requestFailed(500)",
                conflictReason: nil
            )
        )
        XCTAssertFalse(
            WriteQueueRetryPolicy.shouldReplayFailedWrite(
                lastError: "requestFailed(400)",
                conflictReason: nil
            )
        )
    }

    func testReplayPolicyAllowsTransientURLErrorFailuresOnly() {
        XCTAssertTrue(
            WriteQueueRetryPolicy.shouldReplayFailedWrite(
                lastError: "Error Domain=NSURLErrorDomain Code=-1009 \"offline\"",
                conflictReason: nil
            )
        )
        XCTAssertFalse(
            WriteQueueRetryPolicy.shouldReplayFailedWrite(
                lastError: "Error Domain=NSURLErrorDomain Code=-999 \"cancelled\"",
                conflictReason: nil
            )
        )
    }

    func testReplayPolicyRejectsConflictsAndMissingErrors() {
        XCTAssertFalse(
            WriteQueueRetryPolicy.shouldReplayFailedWrite(
                lastError: "requestFailed(500)",
                conflictReason: "server changed"
            )
        )
        XCTAssertFalse(
            WriteQueueRetryPolicy.shouldReplayFailedWrite(
                lastError: nil,
                conflictReason: nil
            )
        )
    }
}

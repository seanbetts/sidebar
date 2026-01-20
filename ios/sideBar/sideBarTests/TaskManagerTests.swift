import XCTest
@testable import sideBar

final class TaskManagerTests: XCTestCase {
    func testManagedTaskRunDebouncedCancelsPrevious() async {
        let manager = ManagedTask()
        let expectation = expectation(description: "debounced")
        expectation.expectedFulfillmentCount = 1

        manager.runDebounced(delay: 0.05) {
            expectation.fulfill()
        }
        manager.runDebounced(delay: 0.05) {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testManagedTaskCancelPreventsDebouncedExecution() async {
        let manager = ManagedTask()
        let expectation = expectation(description: "cancel")
        expectation.isInverted = true

        manager.runDebounced(delay: 0.2) {
            expectation.fulfill()
        }
        manager.cancel()

        await fulfillment(of: [expectation], timeout: 0.4)
    }

    func testPollingTaskRepeatsUntilCanceled() async {
        let polling = PollingTask(interval: 0.05)
        let expectation = expectation(description: "poll")
        expectation.expectedFulfillmentCount = 2
        var count = 0

        polling.start {
            await MainActor.run {
                count += 1
                expectation.fulfill()
                if count >= 2 {
                    polling.cancel()
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

import XCTest
@testable import sideBar

@MainActor
final class RefreshCoordinatorTests: XCTestCase {
    func testCoordinatorCoalescesDuplicateActivationRequestsWhileRefreshIsInFlight() async {
        let adapter = BlockingRefreshAdapter(section: .notes)
        let coordinator = RefreshCoordinator(
            policy: RefreshPolicy(),
            registry: RefreshRegistry(adapters: [adapter])
        )
        let context = RefreshContext(
            visibleSection: .notes,
            hasVisibleDetail: true,
            pinnedSections: [.notes, .websites, .files],
            lastOpenedSection: .tasks,
            staleTargets: []
        )

        let first = Task {
            await coordinator.refresh(trigger: .coldLaunch, context: context)
        }
        let second = Task {
            await coordinator.refresh(trigger: .coldLaunch, context: context)
        }

        await fulfillment(of: [adapter.started], timeout: 1.0)
        XCTAssertEqual(adapter.refreshCount, 1)

        adapter.resume()
        _ = await first.value
        _ = await second.value

        XCTAssertEqual(adapter.refreshCount, 1)
    }
}

@MainActor
private final class BlockingRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection
    let started = XCTestExpectation(description: "refresh adapter started")
    private(set) var refreshCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    init(section: AppSection) {
        self.section = section
    }

    func refresh(plan: RefreshPlan) async {
        refreshCount += 1
        started.fulfill()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

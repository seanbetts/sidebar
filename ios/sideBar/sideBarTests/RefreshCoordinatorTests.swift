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
            staleTargets: [],
            canAttemptServerRead: true
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

    func testCoordinatorCoalescesOverlappingActivationRefreshesAcrossTriggers() async {
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
            staleTargets: [],
            canAttemptServerRead: true
        )

        let launchRefresh = Task {
            await coordinator.refresh(trigger: .coldLaunch, context: context)
        }
        let foregroundRefresh = Task {
            await coordinator.refresh(trigger: .warmForeground, context: context)
        }

        await fulfillment(of: [adapter.started], timeout: 1.0)
        XCTAssertEqual(adapter.refreshCount, 1)

        adapter.resume()
        _ = await launchRefresh.value
        _ = await foregroundRefresh.value

        XCTAssertEqual(adapter.refreshCount, 1)
    }

    func testCoordinatorMarksTargetsFreshAfterRefreshCompletes() async {
        let metadataStore = RefreshMetadataStore()
        var currentNow = Date(timeIntervalSince1970: 1_000)
        let adapter = CountingRefreshAdapter(section: .notes)
        let coordinator = RefreshCoordinator(
            policy: RefreshPolicy(metadataStore: metadataStore, now: { currentNow }),
            registry: RefreshRegistry(adapters: [adapter]),
            now: { currentNow }
        )
        let context = RefreshContext(
            visibleSection: .notes,
            hasVisibleDetail: true,
            pinnedSections: [],
            lastOpenedSection: nil,
            staleTargets: [],
            canAttemptServerRead: true
        )

        await coordinator.refresh(trigger: .coldLaunch, context: context)
        XCTAssertEqual(adapter.refreshCount, 1)

        currentNow = currentNow.addingTimeInterval(30)
        await coordinator.refresh(trigger: .warmForeground, context: context)
        XCTAssertEqual(adapter.refreshCount, 1)

        currentNow = currentNow.addingTimeInterval(200)
        await coordinator.refresh(trigger: .warmForeground, context: context)
        XCTAssertEqual(adapter.refreshCount, 2)
    }

    func testCoordinatorSkipsRefreshWhenServerReadsAreUnavailable() async {
        let adapter = CountingRefreshAdapter(section: .notes)
        let coordinator = RefreshCoordinator(
            policy: RefreshPolicy(),
            registry: RefreshRegistry(adapters: [adapter])
        )

        await coordinator.refresh(
            trigger: .manualRefresh,
            context: RefreshContext(
                visibleSection: .notes,
                hasVisibleDetail: true,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [],
                canAttemptServerRead: false
            )
        )

        XCTAssertEqual(adapter.refreshCount, 0)
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

@MainActor
private final class CountingRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection
    private(set) var refreshCount = 0

    init(section: AppSection) {
        self.section = section
    }

    func refresh(plan: RefreshPlan) async {
        refreshCount += 1
    }
}

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

    func testRegistryPreparesOnlyTheVisibleContentDomain() async {
        let notes = PreparingRefreshAdapter(section: .notes)
        let websites = PreparingRefreshAdapter(section: .websites)
        let registry = RefreshRegistry(adapters: [notes, websites])

        await registry.prepareForPresentation(section: .notes, canAttemptServerRead: true)

        XCTAssertEqual(notes.prepareCalls, [true])
        XCTAssertEqual(websites.prepareCalls, [])
    }

    func testRegistryReportsVisibleDetailAndPinnedMetadataByDomain() {
        let notes = PreparingRefreshAdapter(
            section: .notes,
            hasVisibleDetail: true,
            hasPinnedMetadata: true
        )
        let websites = PreparingRefreshAdapter(
            section: .websites,
            hasVisibleDetail: false,
            hasPinnedMetadata: true
        )
        let registry = RefreshRegistry(adapters: [notes, websites])

        XCTAssertTrue(registry.hasVisibleDetail(for: .notes))
        XCTAssertFalse(registry.hasVisibleDetail(for: .websites))
        XCTAssertFalse(registry.hasVisibleDetail(for: .files))
        XCTAssertEqual(registry.pinnedSections(), [.notes, .websites])
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

@MainActor
private final class PreparingRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection
    let hasVisibleDetail: Bool
    let hasPinnedMetadata: Bool
    private(set) var prepareCalls: [Bool] = []

    init(
        section: AppSection,
        hasVisibleDetail: Bool = false,
        hasPinnedMetadata: Bool = false
    ) {
        self.section = section
        self.hasVisibleDetail = hasVisibleDetail
        self.hasPinnedMetadata = hasPinnedMetadata
    }

    func refresh(plan: RefreshPlan) async {}

    func prepareForPresentation(canAttemptServerRead: Bool) async {
        prepareCalls.append(canAttemptServerRead)
    }
}

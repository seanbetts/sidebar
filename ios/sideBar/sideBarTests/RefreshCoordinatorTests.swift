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

    func testCoordinatorSchedulesRealtimeInvalidationAsCoalescedRefresh() async {
        let adapter = BlockingRefreshAdapter(section: .websites)
        let coordinator = RefreshCoordinator(
            policy: RefreshPolicy(),
            registry: RefreshRegistry(adapters: [adapter])
        )
        let change = realtimeChange(id: "w1")
        let context = realtimeContext()

        let first = Task { await coordinator.scheduleRealtimeInvalidation(change, context: context) }
        let second = Task { await coordinator.scheduleRealtimeInvalidation(change, context: context) }

        await fulfillment(of: [adapter.started], timeout: 1.0)
        XCTAssertEqual(adapter.refreshCount, 1)
        XCTAssertEqual(adapter.clearedTransientChanges, [])

        adapter.resume()
        _ = await first.value
        _ = await second.value

        XCTAssertEqual(adapter.refreshCount, 1)
        XCTAssertEqual(adapter.clearedTransientChanges, [change, change])
    }

    func testCoordinatorClearsDistinctCoalescedRealtimeInvalidationsAfterRefreshCompletes() async {
        let adapter = BlockingRefreshAdapter(section: .websites)
        let coordinator = RefreshCoordinator(
            policy: RefreshPolicy(),
            registry: RefreshRegistry(adapters: [adapter])
        )
        let firstChange = realtimeChange(id: "w1")
        let secondChange = realtimeChange(id: "w2")
        let context = realtimeContext()

        let first = Task { await coordinator.scheduleRealtimeInvalidation(firstChange, context: context) }
        let second = Task { await coordinator.scheduleRealtimeInvalidation(secondChange, context: context) }

        await fulfillment(of: [adapter.started], timeout: 1.0)
        XCTAssertEqual(adapter.refreshCount, 1)
        XCTAssertEqual(adapter.clearedTransientChanges, [])

        adapter.resume()
        _ = await first.value
        _ = await second.value

        XCTAssertEqual(adapter.refreshCount, 1)
        XCTAssertEqual(adapter.clearedTransientChanges.count, 2)
        XCTAssertTrue(adapter.clearedTransientChanges.contains(firstChange))
        XCTAssertTrue(adapter.clearedTransientChanges.contains(secondChange))
    }

    func testCoordinatorAppliesRealtimeMetadataPatchWithoutSchedulingEmptyRefresh() async {
        let adapter = PreparingRefreshAdapter(section: .websites, metadataPatchResult: true)
        let coordinator = RefreshCoordinator(
            policy: RefreshPolicy(),
            registry: RefreshRegistry(adapters: [adapter])
        )
        let change = DomainSyncChange(
            section: .websites,
            entityId: "website-1",
            kind: .metadataPatch,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            requiresListRefresh: false,
            requiresDetailRefresh: false,
            canPatchMetadata: true
        )
        let context = RefreshContext(
            visibleSection: .websites,
            hasVisibleDetail: true,
            pinnedSections: [],
            lastOpenedSection: nil,
            staleTargets: [],
            canAttemptServerRead: true
        )

        await coordinator.scheduleRealtimeInvalidation(change, context: context)

        XCTAssertEqual(adapter.metadataPatchChanges, [change])
        XCTAssertEqual(adapter.refreshPlans, [])
        XCTAssertEqual(adapter.clearedTransientChanges, [change])
    }

    func testCoordinatorSkipsRealtimeRefreshWhenMetadataPatchDeclinesWithoutRefreshTargets() async {
        let adapter = PreparingRefreshAdapter(section: .websites, metadataPatchResult: false)
        let coordinator = RefreshCoordinator(
            policy: RefreshPolicy(),
            registry: RefreshRegistry(adapters: [adapter])
        )
        let change = DomainSyncChange(
            section: .websites,
            entityId: "website-1",
            kind: .metadataPatch,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            requiresListRefresh: false,
            requiresDetailRefresh: false,
            canPatchMetadata: true
        )
        let context = RefreshContext(
            visibleSection: .websites,
            hasVisibleDetail: true,
            pinnedSections: [],
            lastOpenedSection: nil,
            staleTargets: [],
            canAttemptServerRead: true
        )

        await coordinator.scheduleRealtimeInvalidation(change, context: context)

        XCTAssertEqual(adapter.metadataPatchChanges, [change])
        XCTAssertEqual(adapter.refreshPlans, [])
        XCTAssertEqual(adapter.clearedTransientChanges, [])
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

    func testRegistryRoutesMetadataPatchAndTransientClearingByDomain() async {
        let notes = PreparingRefreshAdapter(section: .notes)
        let websites = PreparingRefreshAdapter(section: .websites)
        let registry = RefreshRegistry(adapters: [notes, websites])
        let change = DomainSyncChange(
            section: .websites,
            entityId: "website-1",
            kind: .metadataPatch,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            requiresListRefresh: false,
            requiresDetailRefresh: false,
            canPatchMetadata: true
        )

        let didApplyPatch = await registry.applyMetadataPatch(for: change)
        await registry.clearTransientState(after: change)

        XCTAssertTrue(didApplyPatch)
        XCTAssertEqual(notes.metadataPatchChanges, [])
        XCTAssertEqual(notes.clearedTransientChanges, [])
        XCTAssertEqual(websites.metadataPatchChanges, [change])
        XCTAssertEqual(websites.clearedTransientChanges, [change])
    }

    func testRegistryReturnsFalseWhenMetadataPatchHasNoAdapter() async {
        let registry = RefreshRegistry(adapters: [])
        let change = DomainSyncChange(
            section: .files,
            entityId: "file-1",
            kind: .metadataPatch,
            updatedAt: nil,
            requiresListRefresh: false,
            requiresDetailRefresh: false,
            canPatchMetadata: true
        )

        let didApplyPatch = await registry.applyMetadataPatch(for: change)
        await registry.clearTransientState(after: change)

        XCTAssertFalse(didApplyPatch)
    }

    func testRegistryRoutesSectionRefreshAdapterMetadataHooksThroughExistential() async {
        var patchedChanges: [DomainSyncChange] = []
        var clearedChanges: [DomainSyncChange] = []
        let adapter = SectionRefreshAdapter(
            section: .files,
            refreshList: {},
            applyMetadataPatch: { change in
                patchedChanges.append(change)
                return true
            },
            clearTransientState: { change in
                clearedChanges.append(change)
            }
        )
        let registry = RefreshRegistry(adapters: [adapter])
        let change = DomainSyncChange(
            section: .files,
            entityId: "file-1",
            kind: .metadataPatch,
            updatedAt: nil,
            requiresListRefresh: false,
            requiresDetailRefresh: false,
            canPatchMetadata: true
        )

        let didApplyPatch = await registry.applyMetadataPatch(for: change)
        await registry.clearTransientState(after: change)

        XCTAssertTrue(didApplyPatch)
        XCTAssertEqual(patchedChanges, [change])
        XCTAssertEqual(clearedChanges, [change])
    }

    func testSectionRefreshAdapterCentralizesListAndDetailRefreshChecks() async {
        var prepareCalls: [Bool] = []
        var listRefreshCount = 0
        var detailRefreshCount = 0
        let adapter = SectionRefreshAdapter(
            section: .websites,
            hasVisibleDetail: { true },
            hasPinnedMetadata: { true },
            prepareForPresentation: { canAttemptServerRead in
                prepareCalls.append(canAttemptServerRead)
            },
            refreshesListWhen: { plan, section in
                plan.containsListOrPinnedMetadata(for: section)
            },
            refreshList: {
                listRefreshCount += 1
            },
            refreshVisibleDetail: {
                detailRefreshCount += 1
            }
        )

        XCTAssertTrue(adapter.hasVisibleDetail)
        XCTAssertTrue(adapter.hasPinnedMetadata)

        await adapter.prepareForPresentation(canAttemptServerRead: true)
        await adapter.refresh(
            plan: RefreshPlan(
                trigger: .manualRefresh,
                targets: [.sectionList(.websites), .visibleDetail(.websites)],
                requiresQueueReplayFirst: false
            )
        )
        await adapter.refresh(
            plan: RefreshPlan(
                trigger: .manualRefresh,
                targets: [.chatList],
                requiresQueueReplayFirst: false
            )
        )

        XCTAssertEqual(prepareCalls, [true])
        XCTAssertEqual(listRefreshCount, 1)
        XCTAssertEqual(detailRefreshCount, 1)
    }

    func testSectionRefreshAdapterCentralizesProtectedListPreparation() async {
        var clearCount = 0
        var hydrateCount = 0
        var blockedReadLoadCount = 0
        let prepare = SectionRefreshAdapter.protectedListPreparation(
            clearError: {
                clearCount += 1
            },
            hydrateFromCache: {
                hydrateCount += 1
            },
            loadWhenServerReadUnavailable: {
                blockedReadLoadCount += 1
            }
        )

        await prepare(true)
        await prepare(false)

        XCTAssertEqual(clearCount, 2)
        XCTAssertEqual(hydrateCount, 1)
        XCTAssertEqual(blockedReadLoadCount, 1)
    }

    private func realtimeChange(id: String) -> DomainSyncChange {
        DomainSyncChange(section: .websites, entityId: id, kind: .detailRefresh, updatedAt: nil,
                         requiresListRefresh: true, requiresDetailRefresh: true, canPatchMetadata: false)
    }

    private func realtimeContext() -> RefreshContext {
        RefreshContext(visibleSection: .websites, hasVisibleDetail: true, pinnedSections: [],
                       lastOpenedSection: nil, staleTargets: [], canAttemptServerRead: true)
    }
}

@MainActor
private final class BlockingRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection
    let started = XCTestExpectation(description: "refresh adapter started")
    private(set) var refreshCount = 0
    private(set) var clearedTransientChanges: [DomainSyncChange] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(section: AppSection) { self.section = section }

    func refresh(plan: RefreshPlan) async {
        refreshCount += 1
        started.fulfill()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() { continuation?.resume(); continuation = nil }

    func clearTransientState(after change: DomainSyncChange) async { clearedTransientChanges.append(change) }
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
    let metadataPatchResult: Bool
    private(set) var prepareCalls: [Bool] = []
    private(set) var refreshPlans: [RefreshPlan] = []
    private(set) var metadataPatchChanges: [DomainSyncChange] = []
    private(set) var clearedTransientChanges: [DomainSyncChange] = []

    init(
        section: AppSection,
        hasVisibleDetail: Bool = false,
        hasPinnedMetadata: Bool = false,
        metadataPatchResult: Bool = true
    ) {
        self.section = section
        self.hasVisibleDetail = hasVisibleDetail
        self.hasPinnedMetadata = hasPinnedMetadata
        self.metadataPatchResult = metadataPatchResult
    }

    func refresh(plan: RefreshPlan) async {
        refreshPlans.append(plan)
    }

    func prepareForPresentation(canAttemptServerRead: Bool) async {
        prepareCalls.append(canAttemptServerRead)
    }

    func applyMetadataPatch(for change: DomainSyncChange) async -> Bool {
        metadataPatchChanges.append(change)
        return metadataPatchResult
    }

    func clearTransientState(after change: DomainSyncChange) async {
        clearedTransientChanges.append(change)
    }
}

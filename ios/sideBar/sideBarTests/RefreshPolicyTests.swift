import XCTest
@testable import sideBar

@MainActor
final class RefreshPolicyTests: XCTestCase {
    func testRefreshMetadataStoreTracksAttemptAndSuccessPerTarget() {
        let store = RefreshMetadataStore()
        let attemptDate = Date(timeIntervalSince1970: 100)
        let successDate = Date(timeIntervalSince1970: 150)

        store.markAttempt(for: [.chatList, .sectionList(.notes)], at: attemptDate)
        store.markSuccess(for: [.sectionList(.notes)], at: successDate)

        XCTAssertEqual(
            store.metadata(for: .chatList),
            RefreshTargetMetadata(lastRefreshAt: attemptDate, lastSuccessfulRefreshAt: nil)
        )
        XCTAssertEqual(
            store.metadata(for: .sectionList(.notes)),
            RefreshTargetMetadata(lastRefreshAt: successDate, lastSuccessfulRefreshAt: successDate)
        )
    }

    func testColdLaunchPlanIncludesVisibleTargetsGlobalTargetsAndPinnedMetadata() {
        let policy = RefreshPolicy()
        let plan = policy.makePlan(
            trigger: .coldLaunch,
            context: RefreshContext(
                visibleSection: .notes,
                hasVisibleDetail: true,
                pinnedSections: [.notes, .websites, .files],
                lastOpenedSection: .tasks,
                staleTargets: []
            )
        )

        XCTAssertEqual(plan.trigger, .coldLaunch)
        XCTAssertTrue(plan.targets.contains(.chatList))
        XCTAssertTrue(plan.targets.contains(.taskCounts))
        XCTAssertTrue(plan.targets.contains(.sectionList(.notes)))
        XCTAssertTrue(plan.targets.contains(.visibleDetail(.notes)))
        XCTAssertTrue(plan.targets.contains(.sectionList(.tasks)))
        XCTAssertTrue(plan.targets.contains(.pinnedMetadata(.notes)))
        XCTAssertTrue(plan.targets.contains(.pinnedMetadata(.websites)))
        XCTAssertTrue(plan.targets.contains(.pinnedMetadata(.files)))
        XCTAssertFalse(plan.targets.contains(.archiveList(.notes)))
        XCTAssertFalse(plan.targets.contains(.archiveList(.websites)))
        XCTAssertFalse(plan.requiresQueueReplayFirst)
    }

    func testWarmForegroundPlanOnlyRefreshesStaleVisibleTargets() {
        let policy = RefreshPolicy()
        let plan = policy.makePlan(
            trigger: .warmForeground,
            context: RefreshContext(
                visibleSection: .websites,
                hasVisibleDetail: false,
                pinnedSections: [.notes, .websites, .files],
                lastOpenedSection: .tasks,
                staleTargets: [.sectionList(.websites), .taskCounts]
            )
        )

        XCTAssertEqual(plan.trigger, .warmForeground)
        XCTAssertTrue(plan.targets.contains(.sectionList(.websites)))
        XCTAssertTrue(plan.targets.contains(.taskCounts))
        XCTAssertFalse(plan.targets.contains(.sectionList(.tasks)))
        XCTAssertFalse(plan.targets.contains(.archiveList(.notes)))
        XCTAssertFalse(plan.targets.contains(.archiveList(.websites)))
    }

    func testWarmForegroundPlanUsesMetadataWindowsWhenExplicitStaleTargetsAreEmpty() {
        let metadataStore = RefreshMetadataStore()
        let now = Date(timeIntervalSince1970: 1_000)
        metadataStore.markSuccess(
            for: [.chatList, .sectionList(.websites), .visibleDetail(.websites), .pinnedMetadata(.websites)],
            at: now.addingTimeInterval(-30)
        )
        metadataStore.markSuccess(
            for: [.taskCounts, .pinnedMetadata(.notes)],
            at: now.addingTimeInterval(-600)
        )
        let policy = RefreshPolicy(metadataStore: metadataStore, now: { now })

        let plan = policy.makePlan(
            trigger: .warmForeground,
            context: RefreshContext(
                visibleSection: .websites,
                hasVisibleDetail: true,
                pinnedSections: [.notes, .websites],
                lastOpenedSection: .tasks,
                staleTargets: []
            )
        )

        XCTAssertTrue(plan.targets.contains(.taskCounts))
        XCTAssertTrue(plan.targets.contains(.pinnedMetadata(.notes)))
        XCTAssertFalse(plan.targets.contains(.chatList))
        XCTAssertFalse(plan.targets.contains(.sectionList(.websites)))
        XCTAssertFalse(plan.targets.contains(.visibleDetail(.websites)))
        XCTAssertFalse(plan.targets.contains(.pinnedMetadata(.websites)))
    }

    func testVisibleSectionChangedPlanSkipsFreshVisibleTargets() {
        let metadataStore = RefreshMetadataStore()
        let now = Date(timeIntervalSince1970: 2_000)
        metadataStore.markSuccess(
            for: [.sectionList(.notes), .visibleDetail(.notes)],
            at: now.addingTimeInterval(-30)
        )
        let policy = RefreshPolicy(metadataStore: metadataStore, now: { now })

        let plan = policy.makePlan(
            trigger: .visibleSectionChanged,
            context: RefreshContext(
                visibleSection: .notes,
                hasVisibleDetail: true,
                pinnedSections: [.notes],
                lastOpenedSection: nil,
                staleTargets: []
            )
        )

        XCTAssertTrue(plan.targets.isEmpty)
    }

    func testReconnectPlanRequiresQueueReplayFirstAndKeepsArchivesLazy() {
        let policy = RefreshPolicy()
        let plan = policy.makePlan(
            trigger: .reconnect,
            context: RefreshContext(
                visibleSection: .files,
                hasVisibleDetail: true,
                pinnedSections: [.notes, .websites, .files],
                lastOpenedSection: .chat,
                staleTargets: []
            )
        )

        XCTAssertEqual(plan.trigger, .reconnect)
        XCTAssertTrue(plan.requiresQueueReplayFirst)
        XCTAssertTrue(plan.targets.contains(.sectionList(.files)))
        XCTAssertTrue(plan.targets.contains(.visibleDetail(.files)))
        XCTAssertTrue(plan.targets.contains(.pinnedMetadata(.notes)))
        XCTAssertTrue(plan.targets.contains(.pinnedMetadata(.websites)))
        XCTAssertTrue(plan.targets.contains(.pinnedMetadata(.files)))
        XCTAssertFalse(plan.targets.contains(.archiveList(.notes)))
        XCTAssertFalse(plan.targets.contains(.archiveList(.websites)))
    }
}

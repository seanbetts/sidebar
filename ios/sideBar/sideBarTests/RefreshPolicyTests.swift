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
                staleTargets: [],
                canAttemptServerRead: true
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
                staleTargets: [.sectionList(.websites), .taskCounts],
                canAttemptServerRead: true
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
                staleTargets: [],
                canAttemptServerRead: true
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
                staleTargets: [],
                canAttemptServerRead: true
            )
        )

        XCTAssertTrue(plan.targets.isEmpty)
    }

    func testManualRefreshUsesChatListForChatAndCountsForTasks() {
        let policy = RefreshPolicy()

        let chatPlan = policy.makePlan(
            trigger: .manualRefresh,
            context: RefreshContext(
                visibleSection: .chat,
                hasVisibleDetail: true,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [],
                canAttemptServerRead: true
            )
        )
        let tasksPlan = policy.makePlan(
            trigger: .manualRefresh,
            context: RefreshContext(
                visibleSection: .tasks,
                hasVisibleDetail: false,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [],
                canAttemptServerRead: true
            )
        )

        XCTAssertTrue(chatPlan.targets.contains(.chatList))
        XCTAssertTrue(chatPlan.targets.contains(.visibleDetail(.chat)))
        XCTAssertTrue(tasksPlan.targets.contains(.sectionList(.tasks)))
        XCTAssertTrue(tasksPlan.targets.contains(.taskCounts))
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
                staleTargets: [],
                canAttemptServerRead: true
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

    func testRealtimeInvalidationPlanUsesExplicitStaleTargets() {
        let policy = RefreshPolicy()
        let plan = policy.makePlan(
            trigger: .realtimeInvalidation,
            context: RefreshContext(
                visibleSection: .websites,
                hasVisibleDetail: true,
                pinnedSections: [.websites],
                lastOpenedSection: nil,
                staleTargets: [
                    .visibleDetail(.websites),
                    .sectionList(.websites),
                    .visibleDetail(.websites)
                ],
                canAttemptServerRead: true
            )
        )

        XCTAssertEqual(plan.trigger, .realtimeInvalidation)
        XCTAssertEqual(plan.targets, [.visibleDetail(.websites), .sectionList(.websites)])
        XCTAssertFalse(plan.requiresQueueReplayFirst)
    }

    func testRealtimeInvalidationPlanExpandsTaskListTargetToTaskCounts() {
        let policy = RefreshPolicy()
        let plan = policy.makePlan(
            trigger: .realtimeInvalidation,
            context: RefreshContext(
                visibleSection: .tasks,
                hasVisibleDetail: false,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [.sectionList(.tasks)],
                canAttemptServerRead: true
            )
        )

        XCTAssertEqual(plan.targets, [.sectionList(.tasks), .taskCounts])
        XCTAssertFalse(plan.requiresQueueReplayFirst)
    }

    func testJobTerminalStatePlanUsesExplicitStaleTargets() {
        let policy = RefreshPolicy()
        let plan = policy.makePlan(
            trigger: .jobTerminalState,
            context: RefreshContext(
                visibleSection: .tasks,
                hasVisibleDetail: true,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [
                    .taskCounts,
                    .sectionList(.tasks),
                    .taskCounts
                ],
                canAttemptServerRead: true
            )
        )

        XCTAssertEqual(plan.trigger, .jobTerminalState)
        XCTAssertEqual(plan.targets, [.taskCounts, .sectionList(.tasks)])
        XCTAssertFalse(plan.requiresQueueReplayFirst)
    }

    func testDecodeFailurePlanUsesExplicitStaleTargets() {
        let policy = RefreshPolicy()
        let plan = policy.makePlan(
            trigger: .decodeFailure,
            context: RefreshContext(
                visibleSection: .files,
                hasVisibleDetail: true,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [
                    .sectionList(.files),
                    .visibleDetail(.files),
                    .sectionList(.files)
                ],
                canAttemptServerRead: true
            )
        )

        XCTAssertEqual(plan.trigger, .decodeFailure)
        XCTAssertEqual(plan.targets, [.sectionList(.files), .visibleDetail(.files)])
        XCTAssertFalse(plan.requiresQueueReplayFirst)
    }

    func testRefreshPlanCentralizesTargetMatchingForAdapters() {
        let plan = RefreshPlan(
            trigger: .coldLaunch,
            targets: [
                .chatList,
                .taskCounts,
                .sectionList(.notes),
                .visibleDetail(.files),
                .pinnedMetadata(.websites),
                .archiveList(.notes)
            ],
            requiresQueueReplayFirst: false
        )

        XCTAssertTrue(plan.containsRefreshWork(for: .chat))
        XCTAssertTrue(plan.containsRefreshWork(for: .tasks))
        XCTAssertTrue(plan.containsRefreshWork(for: .notes))
        XCTAssertTrue(plan.containsRefreshWork(for: .files))
        XCTAssertTrue(plan.containsRefreshWork(for: .websites))
        XCTAssertFalse(plan.containsRefreshWork(for: .settings))
    }

    func testRefreshPlanCentralizesCommonDomainTargetGroups() {
        let plan = RefreshPlan(
            trigger: .manualRefresh,
            targets: [.sectionList(.notes), .visibleDetail(.notes), .pinnedMetadata(.files)],
            requiresQueueReplayFirst: false
        )

        XCTAssertTrue(plan.containsListOrPinnedMetadata(for: .notes))
        XCTAssertTrue(plan.containsListOrVisibleDetail(for: .notes))
        XCTAssertTrue(plan.containsVisibleDetail(for: .notes))
        XCTAssertTrue(plan.containsListOrPinnedMetadata(for: .files))
        XCTAssertFalse(plan.containsListOrVisibleDetail(for: .files))
        XCTAssertFalse(plan.containsVisibleDetail(for: .files))
    }
}

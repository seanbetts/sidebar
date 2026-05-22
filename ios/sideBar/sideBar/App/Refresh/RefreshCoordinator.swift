import Foundation

struct ActivationRefreshRequest: Equatable {
    let includeDeferredRefresh: Bool
    let activeSection: AppSection?
    let context: RefreshContext?
}

@MainActor
protocol RefreshCoordinatorType: AnyObject {
    func handleActivation(_ request: ActivationRefreshRequest) async
    func prepareVisibleSectionForPresentation(_ section: AppSection?, canAttemptServerRead: Bool) async
    func hasVisibleDetail(for section: AppSection?) -> Bool
    func pinnedSections() -> [AppSection]
    func refresh(trigger: RefreshTrigger, context: RefreshContext) async
    func scheduleRealtimeInvalidation(_ change: DomainSyncChange, context: RefreshContext) async
    func scheduleDecodeFailureRefresh(section: AppSection, context: RefreshContext) async
    func scheduleJobTerminalRefresh(_ change: DomainSyncChange, context: RefreshContext) async
    func visibleSectionDidChange(to section: AppSection?, context: RefreshContext) async
}

@MainActor
final class RefreshCoordinator: RefreshCoordinatorType {
    private let policy: RefreshPolicy
    private let registry: RefreshRegistry
    private let now: () -> Date
    private var inFlightRefreshes: [RefreshPlan: Task<Void, Never>] = [:]
    private var lastVisibleSection: AppSection?

    init(
        policy: RefreshPolicy? = nil,
        registry: RefreshRegistry? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.policy = policy ?? RefreshPolicy()
        self.registry = registry ?? RefreshRegistry(adapters: [])
        self.now = now
    }

    func handleActivation(_ request: ActivationRefreshRequest) async {
        let trigger: RefreshTrigger = request.includeDeferredRefresh ? .coldLaunch : .warmForeground
        if let context = request.context {
            await refresh(trigger: trigger, context: context)
            return
        }
        guard let activeSection = request.activeSection else { return }
        await refresh(
            trigger: trigger,
            context: RefreshContext(
                visibleSection: activeSection,
                hasVisibleDetail: false,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: [],
                canAttemptServerRead: true
            )
        )
    }

    func prepareVisibleSectionForPresentation(_ section: AppSection?, canAttemptServerRead: Bool) async {
        guard let section else { return }
        await registry.prepareForPresentation(
            section: section,
            canAttemptServerRead: canAttemptServerRead
        )
    }

    func hasVisibleDetail(for section: AppSection?) -> Bool {
        registry.hasVisibleDetail(for: section)
    }

    func pinnedSections() -> [AppSection] {
        registry.pinnedSections()
    }

    func visibleSectionDidChange(to section: AppSection?, context: RefreshContext) async {
        guard section != lastVisibleSection else { return }
        lastVisibleSection = section
        guard section != nil else { return }
        await refresh(trigger: .visibleSectionChanged, context: context)
    }

    func scheduleRealtimeInvalidation(_ change: DomainSyncChange, context: RefreshContext) async {
        guard context.canAttemptServerRead else { return }
        if change.canPatchMetadata {
            let didApplyPatch = await registry.applyMetadataPatch(for: change)
            if didApplyPatch, change.refreshTargets.isEmpty {
                await registry.clearTransientState(after: change)
                return
            }
        }

        guard !change.refreshTargets.isEmpty else { return }
        let didRefresh = await performRefresh(
            trigger: .realtimeInvalidation,
            context: context.with(staleTargets: change.refreshTargets)
        )
        if didRefresh {
            await registry.clearTransientState(after: change)
        }
    }

    func scheduleDecodeFailureRefresh(section: AppSection, context: RefreshContext) async {
        await refresh(
            trigger: .decodeFailure,
            context: context.with(staleTargets: decodeFailureTargets(for: section))
        )
    }

    func scheduleJobTerminalRefresh(_ change: DomainSyncChange, context: RefreshContext) async {
        await refresh(
            trigger: .jobTerminalState,
            context: context.with(staleTargets: change.refreshTargets)
        )
    }

    func refresh(trigger: RefreshTrigger, context: RefreshContext) async {
        await performRefresh(trigger: trigger, context: context)
    }

    @discardableResult
    private func performRefresh(trigger: RefreshTrigger, context: RefreshContext) async -> Bool {
        guard context.canAttemptServerRead else { return false }
        let plan = policy.makePlan(trigger: trigger, context: context)
        guard !plan.targets.isEmpty else { return false }

        if let inFlightRefresh = inFlightRefreshes[plan] {
            await inFlightRefresh.value
            return true
        }

        let task = Task { @MainActor in
            policy.metadataStore?.markAttempt(for: plan.targets, at: now())
            await registry.refresh(plan: plan)
            policy.metadataStore?.markSuccess(for: plan.targets, at: now())
        }
        inFlightRefreshes[plan] = task
        await task.value
        inFlightRefreshes.removeValue(forKey: plan)
        return true
    }

    private func decodeFailureTargets(for section: AppSection) -> [RefreshTarget] {
        [.sectionList(section), .visibleDetail(section)]
    }
}

private extension RefreshContext {
    func with(staleTargets: [RefreshTarget]) -> RefreshContext {
        RefreshContext(
            visibleSection: visibleSection,
            hasVisibleDetail: hasVisibleDetail,
            pinnedSections: pinnedSections,
            lastOpenedSection: lastOpenedSection,
            staleTargets: staleTargets,
            canAttemptServerRead: canAttemptServerRead
        )
    }
}

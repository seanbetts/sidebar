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
    func visibleSectionDidChange(to section: AppSection?, context: RefreshContext) async
}

@MainActor
final class RefreshCoordinator: RefreshCoordinatorType {
    private let policy: RefreshPolicy
    private let registry: RefreshRegistry
    private let now: () -> Date
    private var inFlightPlans = Set<RefreshPlan>()
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

    func refresh(trigger: RefreshTrigger, context: RefreshContext) async {
        guard context.canAttemptServerRead else { return }
        let plan = policy.makePlan(trigger: trigger, context: context)
        guard !plan.targets.isEmpty else { return }
        guard inFlightPlans.insert(plan).inserted else { return }
        defer { inFlightPlans.remove(plan) }
        policy.metadataStore?.markAttempt(for: plan.targets, at: now())
        await registry.refresh(plan: plan)
        policy.metadataStore?.markSuccess(for: plan.targets, at: now())
    }
}

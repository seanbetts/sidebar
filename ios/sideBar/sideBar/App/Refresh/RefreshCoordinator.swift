import Foundation

struct ActivationRefreshRequest: Equatable {
    let includeDeferredRefresh: Bool
    let activeSection: AppSection?
}

@MainActor
protocol RefreshCoordinatorType: AnyObject {
    func handleActivation(_ request: ActivationRefreshRequest) async
    func visibleSectionDidChange(to section: AppSection?)
}

@MainActor
final class RefreshCoordinator: RefreshCoordinatorType {
    private let policy: RefreshPolicy
    private let registry: RefreshRegistry
    private var inFlightPlans = Set<RefreshPlan>()

    init(
        policy: RefreshPolicy? = nil,
        registry: RefreshRegistry? = nil
    ) {
        self.policy = policy ?? RefreshPolicy()
        self.registry = registry ?? RefreshRegistry(adapters: [])
    }

    func handleActivation(_ request: ActivationRefreshRequest) async {
        guard let activeSection = request.activeSection else { return }
        await refresh(
            trigger: .coldLaunch,
            context: RefreshContext(
                visibleSection: activeSection,
                hasVisibleDetail: false,
                pinnedSections: [],
                lastOpenedSection: nil,
                staleTargets: []
            )
        )
    }

    func visibleSectionDidChange(to section: AppSection?) {
        _ = section
    }

    func refresh(trigger: RefreshTrigger, context: RefreshContext) async {
        let plan = policy.makePlan(trigger: trigger, context: context)
        guard inFlightPlans.insert(plan).inserted else { return }
        defer { inFlightPlans.remove(plan) }
        await registry.refresh(plan: plan)
    }
}

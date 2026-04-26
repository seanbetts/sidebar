import Foundation

struct ActivationRefreshRequest: Equatable {
    let includeDeferredRefresh: Bool
    let activeSection: AppSection?
    let context: RefreshContext?
}

@MainActor
protocol RefreshCoordinatorType: AnyObject {
    func handleActivation(_ request: ActivationRefreshRequest) async
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

    func visibleSectionDidChange(to section: AppSection?, context: RefreshContext) async {
        guard section != lastVisibleSection else {
            StartupDebugTrace.log(
                "refresh.visible-section.skip",
                details: [
                    "reason": "unchanged",
                    "section": section?.rawValue ?? "<none>"
                ]
            )
            return
        }
        lastVisibleSection = section
        guard section != nil else {
            StartupDebugTrace.log(
                "refresh.visible-section.skip",
                details: ["reason": "none"]
            )
            return
        }
        await refresh(trigger: .visibleSectionChanged, context: context)
    }

    func refresh(trigger: RefreshTrigger, context: RefreshContext) async {
        guard context.canAttemptServerRead else {
            StartupDebugTrace.log(
                "refresh.skip",
                details: [
                    "reason": "server_read_unavailable",
                    "trigger": trigger.rawValue
                ]
            )
            return
        }
        let plan = policy.makePlan(trigger: trigger, context: context)
        guard !plan.targets.isEmpty else {
            StartupDebugTrace.log(
                "refresh.skip",
                details: [
                    "reason": "empty_plan",
                    "trigger": trigger.rawValue,
                    "visible_section": context.visibleSection?.rawValue ?? "<none>"
                ]
            )
            return
        }
        guard inFlightPlans.insert(plan).inserted else {
            StartupDebugTrace.log(
                "refresh.skip",
                details: [
                    "reason": "duplicate_in_flight",
                    "targets": plan.traceTargets,
                    "trigger": trigger.rawValue
                ]
            )
            return
        }
        defer { inFlightPlans.remove(plan) }
        StartupDebugTrace.log(
            "refresh.start",
            details: [
                "has_visible_detail": context.hasVisibleDetail ? "true" : "false",
                "last_opened": context.lastOpenedSection?.rawValue ?? "<none>",
                "pinned": context.pinnedSections.map(\.rawValue).joined(separator: ","),
                "targets": plan.traceTargets,
                "trigger": trigger.rawValue,
                "visible_section": context.visibleSection?.rawValue ?? "<none>"
            ]
        )
        policy.metadataStore?.markAttempt(for: plan.targets, at: now())
        await registry.refresh(plan: plan)
        policy.metadataStore?.markSuccess(for: plan.targets, at: now())
        StartupDebugTrace.log(
            "refresh.end",
            details: [
                "targets": plan.traceTargets,
                "trigger": trigger.rawValue
            ]
        )
    }
}

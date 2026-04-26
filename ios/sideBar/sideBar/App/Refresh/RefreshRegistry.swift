import Foundation

@MainActor
final class RefreshRegistry {
    private let adapters: [DomainRefreshAdapter]

    init(adapters: [DomainRefreshAdapter]) {
        self.adapters = adapters
    }

    func refresh(plan: RefreshPlan) async {
        for adapter in adapters where shouldRefresh(adapter: adapter, for: plan) {
            StartupDebugTrace.log(
                "refresh.adapter.start",
                details: [
                    "section": adapter.section.rawValue,
                    "targets": plan.traceTargets,
                    "trigger": plan.trigger.rawValue
                ]
            )
            await adapter.refresh(plan: plan)
            StartupDebugTrace.log(
                "refresh.adapter.end",
                details: [
                    "section": adapter.section.rawValue,
                    "targets": plan.traceTargets,
                    "trigger": plan.trigger.rawValue
                ]
            )
        }
    }

    private func shouldRefresh(adapter: DomainRefreshAdapter, for plan: RefreshPlan) -> Bool {
        plan.targets.contains { target in
            switch target {
            case .sectionList(let section),
                    .visibleDetail(let section),
                    .pinnedMetadata(let section),
                    .archiveList(let section):
                return adapter.section == section
            case .chatList:
                return adapter.section == .chat
            case .taskCounts:
                return adapter.section == .tasks
            }
        }
    }
}

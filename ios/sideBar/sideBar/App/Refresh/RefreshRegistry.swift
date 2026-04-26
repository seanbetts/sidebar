import Foundation

@MainActor
final class RefreshRegistry {
    private let adapters: [DomainRefreshAdapter]

    init(adapters: [DomainRefreshAdapter]) {
        self.adapters = adapters
    }

    func refresh(plan: RefreshPlan) async {
        for adapter in adapters where shouldRefresh(adapter: adapter, for: plan) {
            await adapter.refresh(plan: plan)
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

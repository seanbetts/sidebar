import Foundation

@MainActor
final class RefreshRegistry {
    private let adapters: [DomainRefreshAdapter]

    init(adapters: [DomainRefreshAdapter]) {
        self.adapters = adapters
    }

    func prepareForPresentation(section: AppSection, canAttemptServerRead: Bool) async {
        for adapter in adapters where adapter.section == section {
            await adapter.prepareForPresentation(canAttemptServerRead: canAttemptServerRead)
        }
    }

    func hasVisibleDetail(for section: AppSection?) -> Bool {
        guard let section else { return false }
        return adapters.first { $0.section == section }?.hasVisibleDetail ?? false
    }

    func pinnedSections() -> [AppSection] {
        adapters
            .filter(\.hasPinnedMetadata)
            .map(\.section)
    }

    func refresh(plan: RefreshPlan) async {
        for adapter in adapters where shouldRefresh(adapter: adapter, for: plan) {
            await adapter.refresh(plan: plan)
        }
    }

    private func shouldRefresh(adapter: DomainRefreshAdapter, for plan: RefreshPlan) -> Bool {
        plan.containsRefreshWork(for: adapter.section)
    }
}

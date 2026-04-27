import Foundation

@MainActor
final class WebsitesRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .websites
    var hasVisibleDetail: Bool { viewModel.selectedWebsiteId != nil }
    var hasPinnedMetadata: Bool { !viewModel.store.pinnedWebsiteOrder().isEmpty }

    private let viewModel: WebsitesViewModel

    init(viewModel: WebsitesViewModel) {
        self.viewModel = viewModel
    }

    func prepareForPresentation(canAttemptServerRead: Bool) async {
        viewModel.errorMessage = nil
        if canAttemptServerRead {
            viewModel.store.hydrateListFromCache()
        } else {
            await viewModel.load()
        }
    }

    func refresh(plan: RefreshPlan) async {
        if plan.containsListOrPinnedMetadata(for: section) {
            await viewModel.load(force: true)
        }

        if plan.containsVisibleDetail(for: section),
           let websiteId = viewModel.selectedWebsiteId {
            await viewModel.loadById(id: websiteId, force: true)
        }
    }
}

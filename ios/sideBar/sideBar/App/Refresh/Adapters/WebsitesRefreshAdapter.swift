import Foundation

@MainActor
final class WebsitesRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .websites

    private let viewModel: WebsitesViewModel

    init(viewModel: WebsitesViewModel) {
        self.viewModel = viewModel
    }

    func refresh(plan: RefreshPlan) async {
        if plan.targets.contains(.sectionList(.websites)) || plan.targets.contains(.pinnedMetadata(.websites)) {
            await viewModel.load(force: true)
        }

        if plan.targets.contains(.visibleDetail(.websites)),
           let websiteId = viewModel.selectedWebsiteId {
            await viewModel.store.refreshDetail(id: websiteId)
        }
    }
}

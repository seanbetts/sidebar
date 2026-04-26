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
            StartupDebugTrace.log(
                "websites.refresh.list.start",
                details: [
                    "item_count": "\(viewModel.items.count)",
                    "selected": viewModel.selectedWebsiteId ?? "<none>"
                ]
            )
            await viewModel.load(force: true)
            StartupDebugTrace.log(
                "websites.refresh.list.end",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "item_count": "\(viewModel.items.count)",
                    "selected": viewModel.selectedWebsiteId ?? "<none>"
                ]
            )
        }

        if plan.targets.contains(.visibleDetail(.websites)),
           let websiteId = viewModel.selectedWebsiteId {
            StartupDebugTrace.log(
                "websites.refresh.detail.start",
                details: ["website_id": websiteId]
            )
            await viewModel.loadById(id: websiteId, force: true)
            StartupDebugTrace.log(
                "websites.refresh.detail.end",
                details: [
                    "error": viewModel.errorMessage ?? "<none>",
                    "website_id": websiteId
                ]
            )
        }
    }
}

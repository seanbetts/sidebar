import Foundation

final class WebsitesRefreshAdapter: SectionRefreshAdapter {
    init(viewModel: WebsitesViewModel) {
        super.init(
            section: .websites,
            hasVisibleDetail: { viewModel.selectedWebsiteId != nil },
            hasPinnedMetadata: { !viewModel.store.pinnedWebsiteOrder().isEmpty },
            prepareForPresentation: Self.protectedListPreparation(
                clearError: {
                    viewModel.errorMessage = nil
                },
                hydrateFromCache: {
                    viewModel.store.hydrateListFromCache()
                },
                loadWhenServerReadUnavailable: {
                    await viewModel.load()
                }
            ),
            refreshList: {
                await viewModel.load(force: true)
            },
            refreshVisibleDetail: {
                guard let websiteId = viewModel.selectedWebsiteId else { return }
                await viewModel.loadById(id: websiteId, force: true)
            }
        )
    }
}

import Foundation

final class WebsitesRefreshAdapter: SectionRefreshAdapter {
    static func jobTerminalChange(
        entityId: String?,
        requiresDetailRefresh: Bool
    ) -> DomainSyncChange {
        DomainSyncChange(
            section: .websites,
            entityId: entityId,
            kind: .jobProgress,
            updatedAt: nil,
            requiresListRefresh: true,
            requiresDetailRefresh: requiresDetailRefresh,
            canPatchMetadata: false
        )
    }

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

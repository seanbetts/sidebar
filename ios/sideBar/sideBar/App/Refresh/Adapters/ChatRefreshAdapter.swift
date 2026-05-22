import Foundation

final class ChatRefreshAdapter: SectionRefreshAdapter {
    static func classifyConversationChange(
        conversationId: String?,
        updatedAt: Date?,
        affectsSelectedConversation: Bool
    ) -> DomainSyncChange {
        DomainSyncChange(
            section: .chat,
            entityId: conversationId,
            kind: affectsSelectedConversation ? .detailRefresh : .listRefresh,
            updatedAt: updatedAt,
            requiresListRefresh: true,
            requiresDetailRefresh: affectsSelectedConversation,
            canPatchMetadata: false
        )
    }

    init(viewModel: ChatViewModel) {
        super.init(
            section: .chat,
            hasVisibleDetail: { viewModel.selectedConversationId != nil },
            prepareForPresentation: Self.protectedListPreparation(
                clearError: {
                    viewModel.errorMessage = nil
                },
                hydrateFromCache: {
                    await viewModel.chatStore.hydrateConversationsFromCache()
                },
                loadWhenServerReadUnavailable: {
                    await viewModel.loadConversations()
                }
            ),
            refreshesListWhen: { plan, _ in
                plan.contains(.chatList) || plan.contains(.sectionList(.chat))
            },
            refreshList: {
                await viewModel.loadConversations(force: true, silent: true)
            },
            refreshVisibleDetail: {
                guard let conversationId = viewModel.selectedConversationId else { return }
                await viewModel.loadConversation(id: conversationId, silent: true)
            }
        )
    }

    func classifyConversationChange(
        conversationId: String?,
        updatedAt: Date?,
        affectsSelectedConversation: Bool
    ) -> DomainSyncChange {
        Self.classifyConversationChange(
            conversationId: conversationId,
            updatedAt: updatedAt,
            affectsSelectedConversation: affectsSelectedConversation
        )
    }
}

import Foundation

final class ChatRefreshAdapter: SectionRefreshAdapter {
    init(viewModel: ChatViewModel) {
        super.init(
            section: .chat,
            hasVisibleDetail: { viewModel.selectedConversationId != nil },
            prepareForPresentation: { canAttemptServerRead in
                viewModel.errorMessage = nil
                if canAttemptServerRead {
                    await viewModel.chatStore.hydrateConversationsFromCache()
                } else {
                    await viewModel.loadConversations()
                }
            },
            refreshesListWhen: { plan, _ in
                plan.contains(.chatList)
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
}

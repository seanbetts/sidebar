import Foundation

@MainActor
final class ChatRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .chat
    var hasVisibleDetail: Bool { viewModel.selectedConversationId != nil }

    private let viewModel: ChatViewModel

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    func prepareForPresentation(canAttemptServerRead: Bool) async {
        viewModel.errorMessage = nil
        if canAttemptServerRead {
            await viewModel.chatStore.hydrateConversationsFromCache()
        } else {
            await viewModel.loadConversations()
        }
    }

    func refresh(plan: RefreshPlan) async {
        guard plan.containsRefreshWork(for: section) else {
            return
        }

        if plan.contains(.chatList) {
            await viewModel.loadConversations(force: true, silent: true)
        }

        if plan.containsVisibleDetail(for: section),
           let conversationId = viewModel.selectedConversationId {
            await viewModel.loadConversation(id: conversationId, silent: true)
        }
    }
}

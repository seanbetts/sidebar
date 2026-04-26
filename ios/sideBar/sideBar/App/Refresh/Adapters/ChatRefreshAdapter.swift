import Foundation

@MainActor
final class ChatRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection = .chat

    private let viewModel: ChatViewModel

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    func refresh(plan: RefreshPlan) async {
        guard plan.targets.contains(.chatList) || plan.targets.contains(.visibleDetail(.chat)) else {
            return
        }

        if plan.targets.contains(.chatList) {
            await viewModel.loadConversations(force: true, silent: true)
        }

        if plan.targets.contains(.visibleDetail(.chat)),
           let conversationId = viewModel.selectedConversationId {
            await viewModel.loadConversation(id: conversationId, silent: true)
        }
    }
}

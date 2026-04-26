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
            StartupDebugTrace.log(
                "chat.refresh.list.start",
                details: [
                    "conversation_count": "\(viewModel.conversations.count)",
                    "selected": viewModel.selectedConversationId ?? "<none>"
                ]
            )
            await viewModel.loadConversations(force: true, silent: true)
            StartupDebugTrace.log(
                "chat.refresh.list.end",
                details: [
                    "conversation_count": "\(viewModel.conversations.count)",
                    "error": viewModel.errorMessage ?? "<none>",
                    "selected": viewModel.selectedConversationId ?? "<none>"
                ]
            )
        }

        if plan.targets.contains(.visibleDetail(.chat)),
           let conversationId = viewModel.selectedConversationId {
            StartupDebugTrace.log(
                "chat.refresh.detail.start",
                details: ["conversation_id": conversationId]
            )
            await viewModel.loadConversation(id: conversationId, silent: true)
            StartupDebugTrace.log(
                "chat.refresh.detail.end",
                details: [
                    "conversation_id": conversationId,
                    "error": viewModel.errorMessage ?? "<none>"
                ]
            )
        }
    }
}

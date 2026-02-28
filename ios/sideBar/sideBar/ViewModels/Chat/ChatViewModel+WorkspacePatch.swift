import sideBarShared

extension ChatViewModel {
    func handleWorkspacePatch(_ event: ChatStreamEvent) {
        switch ChatWorkspacePatchParser.parse(data: event.data) {
        case .accepted(let actions, let ignoredOperations):
            if ignoredOperations > 0 {
                realtimeLogger.debug(
                    "Ignored \(ignoredOperations, privacy: .public) unsupported workspace patch operations."
                )
            }
            guard !actions.isEmpty else {
                return
            }
            guard let workspaceActionDispatcher else {
                realtimeLogger.debug(
                    "Dropping workspace patch because no workspace dispatcher is configured."
                )
                return
            }
            for action in actions {
                workspaceActionDispatcher(action)
            }

        case .rejected(let reason):
            realtimeLogger.warning(
                "Rejected workspace patch payload: \(reason, privacy: .public)"
            )
        }
    }
}

import OSLog
import sideBarShared

extension ChatViewModel {
    private var workspacePatchLogger: Logger {
        Logger(subsystem: "sideBar", category: "ChatViewModelRealtime")
    }

    func handleWorkspacePatch(_ event: ChatStreamEvent) {
        switch ChatWorkspacePatchParser.parse(data: event.data) {
        case .accepted(let actions, let ignoredOperations):
            if ignoredOperations > 0 {
                workspacePatchLogger.debug(
                    "Ignored \(ignoredOperations) unsupported workspace patch operations."
                )
            }
            guard !actions.isEmpty else {
                return
            }
            guard let workspaceActionDispatcher else {
                workspacePatchLogger.debug(
                    "Dropping workspace patch because no workspace dispatcher is configured."
                )
                return
            }
            for action in actions {
                workspaceActionDispatcher(action)
            }

        case .rejected(let reason):
            workspacePatchLogger.warning(
                "Rejected workspace patch payload: \(reason)"
            )
        }
    }
}

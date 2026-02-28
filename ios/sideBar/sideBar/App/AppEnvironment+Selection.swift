import Foundation

extension AppEnvironment {
    func realtimeClientStopStart() {
        guard authState == .active,
              let userId = container.authSession.userId,
              let token = container.authSession.authorizationToken
        else {
            realtimeClient.stop()
            return
        }
        Task {
            await realtimeClient.start(userId: userId, accessToken: token)
        }
    }

    func observeSelectionChanges() {
        // Phase 7: cross-domain selection is now pane-scoped by workspace visibility.
        // Keep observers disabled to avoid destructive global selection clearing.
    }

    func refreshOnReconnect() {
        guard authState == .active else {
            return
        }
        Task {
            await chatViewModel.refreshConversations(silent: true)
            await chatViewModel.refreshActiveConversation(silent: true)
            await notesViewModel.loadTree()
            await notesViewModel.refreshSelectedNoteIfNeeded()
            await websitesViewModel.load()
            await ingestionViewModel.load()
            await tasksViewModel.load(selection: tasksViewModel.selection, force: true)
            await tasksViewModel.loadCounts(force: true)
            // Refresh widget data to sync with server after reconnect
            await tasksViewModel.refreshWidgetData()
        }
    }
}

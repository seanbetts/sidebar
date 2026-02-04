import Combine
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
        notesViewModel.$selectedNoteId
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.clearNonNoteSelections()
            }
            .store(in: &cancellables)

        websitesViewModel.$selectedWebsiteId
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.clearNonWebsiteSelections()
            }
            .store(in: &cancellables)

        ingestionViewModel.$selectedFileId
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.clearNonFileSelections()
            }
            .store(in: &cancellables)
    }

    private func clearNonNoteSelections() {
        websitesViewModel.clearSelection()
        ingestionViewModel.clearSelection()
        // NOTE: Clear tasks selection once TasksViewModel exists.
    }

    private func clearNonWebsiteSelections() {
        notesViewModel.clearSelection()
        ingestionViewModel.clearSelection()
        // NOTE: Clear tasks selection once TasksViewModel exists.
    }

    private func clearNonFileSelections() {
        notesViewModel.clearSelection()
        websitesViewModel.clearSelection()
        // NOTE: Clear tasks selection once TasksViewModel exists.
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

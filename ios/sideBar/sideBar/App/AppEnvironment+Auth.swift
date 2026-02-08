import Foundation
import sideBarShared

extension AppEnvironment {
    public func refreshAuthState() {
        let previousAuthState = authState
        authState = container.authSession.authState
        let wasAuthenticated = isAuthenticated
        isAuthenticated = authState != .signedOut

        let becameSignedOut = previousAuthState != .signedOut && authState == .signedOut
        let becameStale = previousAuthState != .stale && authState == .stale
        if becameSignedOut {
            container.cacheClient.clear()
            chatStore.reset()
            notesStore.reset()
            websitesStore.reset()
            ingestionStore.reset()
            tasksStore.reset()
            notesViewModel.clearSelection()
            websitesViewModel.clearSelection()
            ingestionViewModel.clearSelection()
            Task {
                await spotlightIndexer.clearAllIndexes()
            }
        }
        if becameStale && wasAuthenticated {
            toastCenter.show(message: "Sync paused — trying to refresh your session.")
        }
        if isAuthenticated {
            biometricMonitor.startMonitoring()
            #if os(iOS) || os(macOS)
            if authState == .active {
                registerDeviceTokenIfNeeded()
            }
            #endif
            Task { [weak self] in
                if self?.authState == .active {
                    await self?.consumePendingShares()
                }
            }
        } else {
            biometricMonitor.stopMonitoring()
        }
        realtimeClientStopStart()

        // Update widget auth state
        WidgetDataManager.shared.updateAuthState(isAuthenticated: isAuthenticated)
    }

    public func beginSignOut() async {
        signOutEvent = UUID()
        #if os(iOS) || os(macOS)
        await disableDeviceTokenIfNeeded()
        #endif
        await container.authSession.signOut()
        refreshAuthState()
    }

    public func consumeExtensionEvents() async {
        await consumePendingShares()
        let events = ExtensionEventStore.shared.consumeEvents()
        guard !events.isEmpty else { return }
        guard authState == .active else { return }
        let websiteEvents = events.filter { $0.type == .websiteSaved }
        guard !websiteEvents.isEmpty else { return }
        for event in websiteEvents {
            if let url = event.websiteUrl {
                websitesViewModel.showPendingFromExtension(url: url)
            }
        }
    }

    /// Consumes pending task completions from widgets and syncs them with the server
    public func consumeWidgetCompletions() async {
        let operations = WidgetDataManager.shared.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self
        )
        let taskIds = operations
            .filter { $0.action == .complete }
            .map { $0.itemId }
        guard !taskIds.isEmpty, authState == .active else { return }

        // Complete each task that was marked done in the widget
        for taskId in taskIds {
            if let task = tasksStore.tasks.first(where: { $0.id == taskId }) {
                await tasksViewModel.completeTask(task: task)
            } else {
                // Task not in current store, try to complete directly via API
                let operation = TaskOperationPayload(
                    operationId: TaskOperationId.make(),
                    op: "complete",
                    id: taskId,
                    clientUpdatedAt: nil
                )
                _ = try? await container.tasksAPI.apply(TaskOperationBatch(operations: [operation]))
            }
        }

        // Refresh tasks to get updated state
        await tasksViewModel.load(selection: .today, force: true)
        await tasksViewModel.loadCounts(force: true)
    }

    /// Consumes pending add task intent from widget and opens the add task UI
    @MainActor
    public func consumeWidgetAddTask() {
        let operations = WidgetDataManager.shared.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self
        )
        guard operations.contains(where: { $0.action == .addNew }), isAuthenticated else { return }

        // Navigate to tasks section and start new task
        commandSelection = .tasks
        #if !os(macOS)
        tasksViewModel.phoneDetailRouteId = TaskSelection.today.cacheKey
        #endif
        if isTasksFocused {
            pendingNewTaskDeepLink = false
            tasksViewModel.startNewTask()
        } else {
            pendingNewTaskDeepLink = true
        }
    }

    /// Consumes pending add note intent from widget and opens the add note UI
    @MainActor
    public func consumeWidgetAddNote() {
        let operations = WidgetDataManager.shared.consumePendingOperations(
            for: .notes,
            actionType: NoteWidgetAction.self
        )
        guard operations.contains(where: { $0.action == .addNew }), isAuthenticated else { return }

        // Navigate to notes section and trigger new note creation
        commandSelection = .notes
        pendingNewNoteDeepLink = true
    }

    /// Consumes pending quick save URL from widget and saves the website
    @MainActor
    public func consumeWidgetQuickSave() async {
        guard let url = WidgetDataManager.shared.consumePendingQuickSave(),
              authState == .active else { return }

        // Navigate to websites and save the URL
        commandSelection = .websites
        _ = await websitesViewModel.saveWebsite(url: url.absoluteString)
    }
}

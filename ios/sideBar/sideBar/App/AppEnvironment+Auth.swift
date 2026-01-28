import Foundation

extension AppEnvironment {
    public func refreshAuthState() {
        let wasAuthenticated = isAuthenticated
        isAuthenticated = container.authSession.accessToken != nil
        if wasAuthenticated && !isAuthenticated {
            container.cacheClient.clear()
            chatStore.reset()
            notesStore.reset()
            websitesStore.reset()
            ingestionStore.reset()
            tasksStore.reset()
            notesViewModel.clearSelection()
            websitesViewModel.clearSelection()
            ingestionViewModel.clearSelection()
            sessionExpiryWarning = nil
        }
        if isAuthenticated {
            biometricMonitor.startMonitoring()
            #if os(iOS) || os(macOS)
            registerDeviceTokenIfNeeded()
            #endif
        } else {
            biometricMonitor.stopMonitoring()
        }
        realtimeClientStopStart()

        // Update widget auth state
        WidgetDataManager.shared.updateAuthState(isAuthenticated: isAuthenticated)
    }

    public func beginSignOut() async {
        signOutEvent = UUID()
        sessionExpiryWarning = nil
        #if os(iOS) || os(macOS)
        await disableDeviceTokenIfNeeded()
        #endif
        await container.authSession.signOut()
        refreshAuthState()
    }

    public func consumeExtensionEvents() async {
        let events = ExtensionEventStore.shared.consumeEvents()
        guard !events.isEmpty else { return }
        guard isAuthenticated else { return }
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
        let taskIds = WidgetDataManager.shared.consumePendingCompletions()
        guard !taskIds.isEmpty, isAuthenticated else { return }

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
        guard WidgetDataManager.shared.consumeAddTaskIntent(), isAuthenticated else { return }

        // Navigate to tasks section and start new task
        commandSelection = .tasks
        pendingNewTaskDeepLink = true
        #if !os(macOS)
        tasksViewModel.phoneDetailRouteId = TaskSelection.today.cacheKey
        #endif
    }
}

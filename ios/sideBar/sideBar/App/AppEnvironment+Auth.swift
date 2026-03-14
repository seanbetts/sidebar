import Foundation
import OSLog
import sideBarShared

extension AppEnvironment {
    private var authLogger: Logger {
        Logger(subsystem: "sideBar", category: "AppEnvironmentAuth")
    }

    public func refreshAuthState() {
        let previousAuthState = authState
        authState = container.authSession.authState
        let wasAuthenticated = previousAuthState != .signedOut
        let isAuthenticated = authState != .signedOut

        let storedCacheScopeUserId = storage.userDefaults.string(forKey: AppStorageKeys.cacheScopeUserId)
        let requiresSignedOutReset = authState == .signedOut
            && (previousAuthState != .signedOut || storedCacheScopeUserId != nil)
        let becameStale = previousAuthState != .stale && authState == .stale
        if requiresSignedOutReset {
            clearStoredCacheScopeUserId()
            resetSignedInData(clearNavigationState: true)
        }
        if becameStale && wasAuthenticated {
            toastCenter.show(message: "Sync paused — trying to refresh your session.")
        }
        if isAuthenticated {
            reconcileCacheScopeForAuthenticatedUser()
            biometricMonitor.startMonitoring()
            if authState == .active {
                currentLocationViewModel.startTracking()
            }
            #if os(iOS) || os(macOS)
            if authState == .active {
                registerDeviceTokenIfNeeded()
            }
            #endif
            Task { [weak self] in
                if self?.authState == .active {
                    await self?.consumeExtensionEvents()
                }
            }
        } else {
            biometricMonitor.stopMonitoring()
            currentLocationViewModel.stopTracking()
        }
        realtimeClientStopStart()

        // Update widget auth state
        storage.widgetDataManager.updateAuthState(isAuthenticated: isAuthenticated)
    }

    private func reconcileCacheScopeForAuthenticatedUser() {
        guard let currentUserId = currentAuthUserId else { return }
        let defaults = storage.userDefaults
        let storedUserId = defaults.string(forKey: AppStorageKeys.cacheScopeUserId)
        guard storedUserId != currentUserId else { return }

        // Run a one-time migration clear for existing installs with unscoped cache keys.
        let shouldResetSignedInData = storedUserId != nil || authState == .active
        if shouldResetSignedInData {
            let previousScope = storedUserId ?? "<none>"
            authLogger.notice(
                """
                Resetting cached data for user scope change from \
                \(previousScope, privacy: .public) to \(currentUserId, privacy: .public)
                """
            )
            resetSignedInData(clearNavigationState: false)
        }
        defaults.set(currentUserId, forKey: AppStorageKeys.cacheScopeUserId)
    }

    private var currentAuthUserId: String? {
        guard let rawUserId = container.authSession.userId else { return nil }
        let trimmedUserId = rawUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserId.isEmpty else { return nil }
        return trimmedUserId
    }

    private func clearStoredCacheScopeUserId() {
        storage.userDefaults.removeObject(forKey: AppStorageKeys.cacheScopeUserId)
    }

    private func resetSignedInData(clearNavigationState: Bool) {
        dismissMacSettings()
        flushSignedInPersistence()
        chatStore.reset()
        notesStore.reset()
        websitesStore.reset()
        ingestionStore.reset()
        tasksStore.reset()
        chatViewModel.reset()
        tasksViewModel.reset()
        settingsViewModel.reset()
        notesViewModel.clearSelection()
        notesViewModel.searchQuery = ""
        websitesViewModel.clearSelection()
        websitesViewModel.panelSearchQuery = ""
        websitesViewModel.errorMessage = nil
        websitesViewModel.saveErrorMessage = nil
        websitesViewModel.pendingWebsite = nil
        websitesViewModel.isSavingWebsite = false
        ingestionViewModel.clearSelection()
        ingestionViewModel.panelSearchQuery = ""
        ingestionViewModel.errorMessage = nil
        currentLocationViewModel.stopTracking()
        if clearNavigationState {
            isTasksFocused = false
            navigation.resetForSignOut()
        }
        Task {
            await spotlightIndexer.clearAllIndexes()
        }
    }

    private func flushSignedInPersistence() {
        container.cacheClient.clear()
        offlineStore.clearAllSnapshots()
        let defaults = storage.userDefaults
        defaults.removeObject(forKey: AppStorageKeys.lastSignInEmail)
        defaults.removeObject(forKey: AppStorageKeys.lastAuthTimestamp)
        storage.widgetDataManager.clearAllDataForSignOut()
        storage.pendingShareStore.clearAll()
        storage.extensionEventStore.clear()
        do {
            try draftStorage.clearAllDrafts()
        } catch {
            authLogger.error("Failed to clear local drafts on sign-out: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func beginSignOut() async {
        signOutEvent = UUID()
        #if os(iOS) || os(macOS)
        await disableDeviceTokenIfNeeded()
        #endif
        await container.authSession.signOut()
        refreshAuthState()
    }

    /// Handles signed-in foreground activation work shared by iOS and macOS.
    public func handleSignedInActivation(includeDeferredRefresh: Bool = true) async {
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "app_activation",
            stage: "begin",
            message: "Handling signed-in activation.",
            metadata: ["auth_state": authState.rawValue]
        )
        if authState != .signedOut {
            if authState == .stale {
                await container.authSession.refreshSession()
            } else {
                await container.authSession.refreshSessionIfStale()
            }
        }

        if authState == .active {
            await consumeExtensionEvents()
            await consumeWidgetCompletions()
            await consumeWidgetQuickSave()
            if includeDeferredRefresh {
                await refreshWidgetDataBridges()
            }
        }
        consumeWidgetAddTask()
        consumeWidgetAddNote()
        #if os(iOS)
        if includeDeferredRefresh {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if authState == .active {
                await consumeExtensionEvents()
                await websitesViewModel.load(force: true)
            }
        }
        runOfflineMaintenance()
        #endif
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "app_activation",
            stage: "end",
            message: "Finished signed-in activation.",
            metadata: ["auth_state": authState.rawValue]
        )
    }

    private func refreshWidgetDataBridges() async {
        async let tasks: () = tasksViewModel.refreshWidgetData()
        async let notes: () = notesViewModel.refreshWidgetData()
        async let websites: () = websitesViewModel.refreshWidgetData()
        async let files: () = ingestionViewModel.refreshWidgetData()
        _ = await (tasks, notes, websites, files)
    }

    public func consumeExtensionEvents() async {
        guard authState == .active else { return }
        await consumePendingShares()
        let events = storage.extensionEventStore.consumeEvents()
        guard !events.isEmpty else { return }

        var enqueuedWebsiteEvents = false
        for event in events where event.type == .websiteSaved {
            if let website = event.website {
                await applySavedWebsiteEvent(website)
                continue
            }
            guard let url = event.websiteUrl,
                  let normalized = ExtensionURLMessageHandler.normalizeQueuedURL(url) else {
                continue
            }
            if storage.pendingShareStore.enqueueWebsite(url: normalized) != nil {
                enqueuedWebsiteEvents = true
            }
        }

        if enqueuedWebsiteEvents {
            websitesViewModel.syncPendingWebsitesFromQueuedShares(storage.pendingShareStore.loadAll())
        }
    }

    private func applySavedWebsiteEvent(_ website: ExtensionSavedWebsite) async {
        let item = WebsiteItem(
            id: website.id,
            title: website.title,
            url: website.url,
            domain: website.domain,
            savedAt: website.savedAt,
            publishedAt: website.publishedAt,
            pinned: website.pinned,
            pinnedOrder: website.pinnedOrder,
            archived: website.archived,
            faviconUrl: website.faviconUrl,
            faviconR2Key: website.faviconR2Key,
            youtubeTranscripts: website.youtubeTranscripts,
            readingTime: website.readingTime,
            updatedAt: website.updatedAt,
            lastOpenedAt: website.lastOpenedAt,
            deletedAt: nil
        )
        if let detail = await resolvedSavedWebsiteDetail(from: website) {
            websitesStore.persistDetail(detail)
            websitesStore.insertItemAtTop(WebsiteItem(detail: detail), persist: true)
        } else {
            websitesStore.insertItemAtTop(item, persist: true)
        }
        websitesStore.invalidateList()
        websitesViewModel.removePendingWebsite(for: website.url)
    }

    private func resolvedSavedWebsiteDetail(from website: ExtensionSavedWebsite) async -> WebsiteDetail? {
        if let content = website.content, website.requiresDetailFetch == false {
            return WebsiteDetail(
                id: website.id,
                title: website.title,
                url: website.url,
                urlFull: website.urlFull,
                domain: website.domain,
                content: content,
                source: website.source,
                savedAt: website.savedAt,
                publishedAt: website.publishedAt,
                pinned: website.pinned,
                pinnedOrder: website.pinnedOrder,
                archived: website.archived,
                faviconUrl: website.faviconUrl,
                faviconR2Key: website.faviconR2Key,
                youtubeTranscripts: website.youtubeTranscripts,
                readingTime: website.readingTime,
                updatedAt: website.updatedAt,
                lastOpenedAt: website.lastOpenedAt
            )
        }

        do {
            return try await websitesStore.api.get(id: website.id)
        } catch {
            authLogger.error(
                """
                Failed to hydrate saved website event detail for \
                \(website.id, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """
            )
            return nil
        }
    }

    /// Consumes pending task completions from widgets and syncs them with the server
    public func consumeWidgetCompletions() async {
        let operations = storage.widgetDataManager.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self,
            matching: { $0 == .complete }
        )
        let taskIds = operations
            .map { $0.itemId.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !taskIds.isEmpty, authState == .active else { return }

        // Complete each task that was marked done in the widget
        for taskId in taskIds {
            guard IdentifierValidation.isServerTaskID(taskId) else {
                authLogger.error(
                    "Skipping widget completion with invalid task ID \(taskId, privacy: .public)"
                )
                continue
            }
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
                do {
                    _ = try await container.tasksAPI.apply(TaskOperationBatch(operations: [operation]))
                } catch {
                    authLogger.error(
                        "Failed to apply widget completion for task \(taskId, privacy: .public)"
                    )
                    authLogger.error(
                        "Widget completion apply error: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        // Refresh tasks to get updated state
        await tasksViewModel.load(selection: .today, force: true)
        await tasksViewModel.loadCounts(force: true)
    }

    /// Consumes pending add task intent from widget and opens the add task UI
    @MainActor
    public func consumeWidgetAddTask() {
        let operations = storage.widgetDataManager.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self,
            matching: { $0 == .addNew }
        )
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "widget_bridge_app",
            stage: "consume_add_task",
            message: "Consumed widget add-task operations.",
            metadata: ["count": "\(operations.count)"]
        )
        guard operations.contains(where: { $0.action == .addNew }), isAuthenticated else { return }

        // Navigate to tasks section and start new task
        AppSentry.recordAction(
            category: "widget",
            name: "Started New Task from Widget",
            data: ["source": "widget_add_task"]
        )
        routeWorkspaceSelection(to: .tasks, source: "widget_add_task")
        #if !os(macOS)
        tasksPhoneDetailRouteId = TaskSelection.today.cacheKey
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
        let operations = storage.widgetDataManager.consumePendingOperations(
            for: .notes,
            actionType: NoteWidgetAction.self,
            matching: { $0 == .addNew }
        )
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "widget_bridge_app",
            stage: "consume_add_note",
            message: "Consumed widget add-note operations.",
            metadata: ["count": "\(operations.count)"]
        )
        guard operations.contains(where: { $0.action == .addNew }), isAuthenticated else { return }

        // Navigate to notes section and trigger new note creation
        AppSentry.recordAction(
            category: "widget",
            name: "Started New Note from Widget",
            data: ["source": "widget_add_note"]
        )
        routeWorkspaceSelection(to: .notes, source: "widget_add_note")
        pendingNewNoteDeepLink = true
    }

    /// Consumes pending quick save URL from widget and saves the website
    @MainActor
    public func consumeWidgetQuickSave() async {
        guard let url = storage.widgetDataManager.consumePendingQuickSave(),
              authState == .active else { return }
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "widget_bridge_app",
            stage: "consume_quick_save",
            message: "Consumed widget quick-save URL.",
            metadata: ["url": url.absoluteString]
        )

        // Navigate to websites and save the URL
        AppSentry.recordAction(
            category: "widget",
            name: "Quick Save from Widget",
            data: ["source": "widget_quick_save"]
        )
        routeWorkspaceSelection(to: .websites, source: "widget_quick_save")
        _ = await enqueueWebsiteSave(url: url.absoluteString, selectAfterSave: true)
    }
}

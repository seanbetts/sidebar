import Foundation
import OSLog
import sideBarShared

extension AppEnvironment {
    private var authBridgeLogger: Logger {
        Logger(subsystem: "sideBar", category: "AppEnvironmentAuth")
    }

    func refreshWidgetDataBridges() async {
        async let tasks: () = tasksViewModel.refreshWidgetData()
        async let notes: () = notesViewModel.refreshWidgetData()
        async let websites: () = websitesViewModel.refreshWidgetData()
        async let files: () = ingestionViewModel.refreshWidgetData()
        _ = await (tasks, notes, websites, files)
    }

    public func consumeExtensionEvents(awaitPendingShareReplay: Bool = true) async {
        guard authState == .active, isProtectedContentReady else { return }
        if awaitPendingShareReplay {
            await consumePendingShares()
        }
        let events = storage.extensionEventStore.consumeEvents()
        let hasQueuedWebsiteItems = storage.pendingShareStore.loadAll().contains { $0.kind == .website }
        guard !events.isEmpty || hasQueuedWebsiteItems else { return }

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

        guard !awaitPendingShareReplay else { return }
        guard hasQueuedWebsiteItems || enqueuedWebsiteEvents else { return }
        let replayStartSignal = PendingShareReplayStartSignal()
        let replayTask = Task { [weak self] in
            await self?.consumePendingShares(replayStartSignal: replayStartSignal)
        }
        // Wait until replay has entered the queued-save path before letting
        // foreground refresh work observe the list.
        await replayStartSignal.wait()
        _ = replayTask
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
        clearQueuedWebsiteEntries(matching: website.url)
        websitesViewModel.removePendingWebsite(for: website.url)
    }

    private func clearQueuedWebsiteEntries(matching rawURL: String) {
        let target = websitesViewModel.canonicalWebsiteURLForPendingMatch(rawURL) ?? rawURL
        let existing = storage.pendingShareStore.loadAll()
        let filtered = existing.filter { item in
            guard item.kind == .website, let itemURL = item.url else { return true }
            let candidate = websitesViewModel.canonicalWebsiteURLForPendingMatch(itemURL) ?? itemURL
            return candidate != target
        }
        guard filtered.count != existing.count else { return }
        storage.pendingShareStore.replaceAll(filtered)
        websitesViewModel.syncPendingWebsitesFromQueuedShares(filtered)
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
            authBridgeLogger.error(
                """
                Failed to hydrate saved website event detail for \
                \(website.id, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """
            )
            return nil
        }
    }

    public func consumeWidgetCompletions() async {
        guard authState == .active else { return }
        let operations = storage.widgetDataManager.consumePendingOperations(
            for: .tasks,
            actionType: TaskWidgetAction.self,
            matching: { $0 == .complete }
        )
        let taskIds = operations
            .map { $0.itemId.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !taskIds.isEmpty else { return }

        var appliedAny = false
        var failedOperations: [WidgetPendingOperation<TaskWidgetAction>] = []

        for operation in operations {
            let taskId = operation.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard IdentifierValidation.isServerTaskID(taskId) else {
                authBridgeLogger.error(
                    "Skipping widget completion with invalid task ID \(taskId, privacy: .public)"
                )
                continue
            }
            if let task = tasksStore.tasks.first(where: { $0.id == taskId }) {
                let didApply = await tasksViewModel.completeTask(task: task)
                if didApply {
                    appliedAny = true
                } else {
                    failedOperations.append(operation)
                }
            } else {
                let applyOperation = TaskOperationPayload(
                    operationId: TaskOperationId.make(),
                    op: "complete",
                    id: taskId,
                    clientUpdatedAt: nil
                )
                do {
                    _ = try await container.tasksAPI.apply(
                        TaskOperationBatch(operations: [applyOperation])
                    )
                    appliedAny = true
                } catch {
                    authBridgeLogger.error(
                        "Failed to apply widget completion for task \(taskId, privacy: .public)"
                    )
                    authBridgeLogger.error(
                        "Widget completion apply error: \(error.localizedDescription, privacy: .public)"
                    )
                    failedOperations.append(operation)
                }
            }
        }

        for failedOperation in failedOperations {
            storage.widgetDataManager.recordPendingOperation(failedOperation, for: .tasks)
        }

        guard appliedAny else { return }
        await tasksViewModel.load(selection: .today, force: true)
        await tasksViewModel.loadCounts(force: true)
    }

    @MainActor
    public func consumeWidgetAddTask() {
        guard isAuthenticated else { return }
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
        guard operations.contains(where: { $0.action == .addNew }) else { return }

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

    @MainActor
    public func consumeWidgetAddNote() {
        guard isAuthenticated else { return }
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
        guard operations.contains(where: { $0.action == .addNew }) else { return }

        AppSentry.recordAction(
            category: "widget",
            name: "Started New Note from Widget",
            data: ["source": "widget_add_note"]
        )
        routeWorkspaceSelection(to: .notes, source: "widget_add_note")
        pendingNewNoteDeepLink = true
    }

    @MainActor
    public func consumeWidgetQuickSave() async {
        guard authState == .active,
              let url = storage.widgetDataManager.consumePendingQuickSave() else { return }
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "widget_bridge_app",
            stage: "consume_quick_save",
            message: "Consumed widget quick-save URL.",
            metadata: ["url": url.absoluteString]
        )

        AppSentry.recordAction(
            category: "widget",
            name: "Quick Save from Widget",
            data: ["source": "widget_quick_save"]
        )
        routeWorkspaceSelection(to: .websites, source: "widget_quick_save")
        _ = await enqueueWebsiteSave(url: url.absoluteString, selectAfterSave: true)
    }
}

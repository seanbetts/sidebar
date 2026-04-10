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

}

import Foundation

extension TasksViewModel {
    public func applyTaskRealtimeEvent(_ payload: RealtimePayload<TaskRealtimeRecord>) async {
        _ = payload
        scheduleRealtimeRefresh()
    }

    public func applyTaskProjectRealtimeEvent(_ payload: RealtimePayload<TaskProjectRealtimeRecord>) async {
        _ = payload
        scheduleRealtimeRefresh()
    }

    public func applyTaskGroupRealtimeEvent(_ payload: RealtimePayload<TaskGroupRealtimeRecord>) async {
        _ = payload
        scheduleRealtimeRefresh()
    }

    func setLocalErrorMessage(_ message: String?) {
        localErrorMessage = message
    }

    private func scheduleRealtimeRefresh() {
        guard !shouldQueueTaskWrites else {
            return
        }
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.realtimeRefreshDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.realtimeRefreshDelayNanoseconds)
            }
            guard !Task.isCancelled else { return }

            let currentSelection = self.selection
            if currentSelection != .none {
                // Reconcile from cache first, then refresh in background to avoid UI flicker.
                await self.load(selection: currentSelection)
            }
            await self.loadCounts()
            await self.refreshWidgetData()
        }
    }

    public func refreshAfterExternalTaskChange(force: Bool = true) async {
        let currentSelection = selection
        if currentSelection != .none {
            await load(selection: currentSelection, force: force)
        }
        await loadCounts(force: force)
        await refreshWidgetData()
    }
}

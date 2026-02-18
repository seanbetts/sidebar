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
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }

            let currentSelection = self.selection
            if currentSelection != .none {
                await self.load(selection: currentSelection, force: true)
            }
            await self.loadCounts(force: true)
            await self.refreshWidgetData()
        }
    }
}

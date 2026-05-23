import Foundation

extension TasksViewModel {
    public func applyTaskRealtimeEvent(_ payload: RealtimePayload<TaskRealtimeRecord>) async {
        await invalidateTaskRealtime(
            entityId: payload.record?.id ?? payload.oldRecord?.id,
            updatedAt: DateParsing.parseISO8601(payload.record?.updatedAt ?? payload.oldRecord?.updatedAt),
            isDeleted: payload.eventType == .delete || payload.record?.deletedAt != nil
        )
    }

    public func applyTaskProjectRealtimeEvent(_ payload: RealtimePayload<TaskProjectRealtimeRecord>) async {
        await invalidateTaskRealtime(
            entityId: payload.record?.id ?? payload.oldRecord?.id,
            updatedAt: DateParsing.parseISO8601(payload.record?.updatedAt ?? payload.oldRecord?.updatedAt),
            isDeleted: payload.eventType == .delete || payload.record?.deletedAt != nil
        )
    }

    public func applyTaskGroupRealtimeEvent(_ payload: RealtimePayload<TaskGroupRealtimeRecord>) async {
        await invalidateTaskRealtime(
            entityId: payload.record?.id ?? payload.oldRecord?.id,
            updatedAt: DateParsing.parseISO8601(payload.record?.updatedAt ?? payload.oldRecord?.updatedAt),
            isDeleted: payload.eventType == .delete || payload.record?.deletedAt != nil
        )
    }

    func setLocalErrorMessage(_ message: String?) {
        localErrorMessage = message
    }

    private func invalidateTaskRealtime(entityId: String?, updatedAt: Date?, isDeleted: Bool) async {
        let change = TasksRefreshAdapter.classifyTaskRealtime(
            entityId: entityId,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
        await onRealtimeInvalidation?(change)
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

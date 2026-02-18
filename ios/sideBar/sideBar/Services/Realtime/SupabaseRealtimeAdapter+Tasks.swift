import Foundation
import sideBarShared
import OSLog

extension SupabaseRealtimeAdapter {
    func handleTaskInsert(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: TaskRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyTaskEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("Tasks insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleTaskUpdate(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: TaskRealtimeRecord = try action.decodeRecord(decoder: decoder)
            var oldRecord: TaskRealtimeRecord?
            do {
                oldRecord = try action.decodeOldRecord(decoder: decoder)
            } catch {
                logger.error("Tasks update old record decode failed: \(error.localizedDescription, privacy: .public)")
            }
            notifyTaskEvent(type: .update, record: record, oldRecord: oldRecord)
        } catch {
            logger.error("Tasks update decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleTaskDelete(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let oldRecord: TaskRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyTaskEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("Tasks delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleTaskProjectInsert(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: TaskProjectRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyTaskProjectEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("Task projects insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleTaskProjectUpdate(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: TaskProjectRealtimeRecord = try action.decodeRecord(decoder: decoder)
            var oldRecord: TaskProjectRealtimeRecord?
            do {
                oldRecord = try action.decodeOldRecord(decoder: decoder)
            } catch {
                logger.error("Task projects update old record decode failed: \(error.localizedDescription, privacy: .public)")
            }
            notifyTaskProjectEvent(type: .update, record: record, oldRecord: oldRecord)
        } catch {
            logger.error("Task projects update decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleTaskProjectDelete(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let oldRecord: TaskProjectRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyTaskProjectEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("Task projects delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleTaskGroupInsert(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: TaskGroupRealtimeRecord = try action.decodeRecord(decoder: decoder)
            notifyTaskGroupEvent(type: .insert, record: record, oldRecord: nil)
        } catch {
            logger.error("Task groups insert decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleTaskGroupUpdate(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let record: TaskGroupRealtimeRecord = try action.decodeRecord(decoder: decoder)
            var oldRecord: TaskGroupRealtimeRecord?
            do {
                oldRecord = try action.decodeOldRecord(decoder: decoder)
            } catch {
                logger.error("Task groups update old record decode failed: \(error.localizedDescription, privacy: .public)")
            }
            notifyTaskGroupEvent(type: .update, record: record, oldRecord: oldRecord)
        } catch {
            logger.error("Task groups update decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleTaskGroupDelete(_ action: RealtimeActionDecoding) {
        do {
            let decoder = Self.makeDecoder()
            let oldRecord: TaskGroupRealtimeRecord = try action.decodeOldRecord(decoder: decoder)
            notifyTaskGroupEvent(type: .delete, record: nil, oldRecord: oldRecord)
        } catch {
            logger.error("Task groups delete decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func notifyTaskEvent(
        type: RealtimeEventType,
        record: TaskRealtimeRecord?,
        oldRecord: TaskRealtimeRecord?
    ) {
        let payload = RealtimePayload(
            eventType: type,
            table: RealtimeTable.tasks,
            schema: "public",
            record: record,
            oldRecord: oldRecord
        )
        Task { @MainActor [weak self] in
            self?.handler?.handleTaskEvent(payload)
        }
    }

    private func notifyTaskProjectEvent(
        type: RealtimeEventType,
        record: TaskProjectRealtimeRecord?,
        oldRecord: TaskProjectRealtimeRecord?
    ) {
        let payload = RealtimePayload(
            eventType: type,
            table: RealtimeTable.taskProjects,
            schema: "public",
            record: record,
            oldRecord: oldRecord
        )
        Task { @MainActor [weak self] in
            self?.handler?.handleTaskProjectEvent(payload)
        }
    }

    private func notifyTaskGroupEvent(
        type: RealtimeEventType,
        record: TaskGroupRealtimeRecord?,
        oldRecord: TaskGroupRealtimeRecord?
    ) {
        let payload = RealtimePayload(
            eventType: type,
            table: RealtimeTable.taskGroups,
            schema: "public",
            record: record,
            oldRecord: oldRecord
        )
        Task { @MainActor [weak self] in
            self?.handler?.handleTaskGroupEvent(payload)
        }
    }
}

/// Represents TaskRealtimeRecord.
public struct TaskRealtimeRecord: Codable {
    public let id: String
    public let title: String?
    public let status: String?
    public let deadline: String?
    public let notes: String?
    public let projectId: String?
    public let groupId: String?
    public let repeating: Bool?
    public let repeatTemplate: Bool?
    public let recurrenceRule: RecurrenceRule?
    public let nextInstanceDate: String?
    public let updatedAt: String?
    public let deletedAt: String?
}

/// Represents TaskProjectRealtimeRecord.
public struct TaskProjectRealtimeRecord: Codable {
    public let id: String
    public let title: String?
    public let groupId: String?
    public let status: String?
    public let updatedAt: String?
    public let deletedAt: String?
}

/// Represents TaskGroupRealtimeRecord.
public struct TaskGroupRealtimeRecord: Codable {
    public let id: String
    public let title: String?
    public let updatedAt: String?
    public let deletedAt: String?
}

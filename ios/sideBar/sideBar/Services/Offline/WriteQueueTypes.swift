import Foundation

enum WriteOperation: String {
    case create
    case update
    case delete
    case rename
    case pin
    case archive
    case move
    case copy
}

enum WriteEntityType: String, Codable {
    case note
    case task
    case message
    case website
    case file
    case scratchpad
}

enum WriteQueueStatus: String {
    case pending
    case inProgress
    case failed
}

struct PendingWriteSummary: Identifiable {
    let id: UUID
    let operationType: String
    let entityType: String
    let entityId: String?
    let status: String
    let attempts: Int16
    let lastError: String?
    let conflictReason: String?
    let createdAt: Date
    let lastAttemptAt: Date?
}

struct PendingWriteRecord: Sendable, Equatable {
    let id: UUID
    let operationType: String
    let entityType: String
    let entityId: String?
    let payload: Data
    let serverSnapshot: Data?
    let attempts: Int16
}

enum WriteQueueError: Error {
    case missingExecutor
    case missingQueue
    case queueFull
    case unknownEntityType(String)
}

struct WriteQueueConflictError: Error {
    let reason: String
    let serverSnapshot: Data?
}

enum WriteQueueConflictResolution {
    case keepLocal
    case keepServer
}

@MainActor
protocol WriteQueueExecutor {
    func execute(write: PendingWriteRecord) async throws
}

import Foundation

/// Captures a local vs server conflict for sync resolution.
public struct SyncConflict<T: Codable & Equatable>: Codable, Equatable {
    public let entityId: String
    public let local: T
    public let server: T
    public let reason: String

    public init(entityId: String, local: T, server: T, reason: String) {
        self.entityId = entityId
        self.local = local
        self.server = server
        self.reason = reason
    }
}

import Foundation

/// Lifecycle state for a locally stored AI work snapshot.
public enum AIWorkStatus: String, Codable, Sendable, Equatable {
    case queued
    case running
    case completed
    case failedRecoverable = "failed_recoverable"
    case cancelled
}

/// Durable payload and route metadata for capability-scoped local AI work.
public struct AIWorkSnapshot: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let capability: IntelligenceCapability
    public let status: AIWorkStatus
    public let routeMetadata: IntelligenceRouteMetadata?
    public let payload: Data
    public let updatedAt: Date

    public init(
        id: UUID,
        capability: IntelligenceCapability,
        status: AIWorkStatus,
        routeMetadata: IntelligenceRouteMetadata?,
        payload: Data,
        updatedAt: Date
    ) {
        self.id = id
        self.capability = capability
        self.status = status
        self.routeMetadata = routeMetadata
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// Capability-scoped local persistence for reusable AI work snapshots.
public final class AIWorkLocalStore {
    private static let entityType = "aiWork"

    private let offlineStore: OfflineStore

    /// Creates a local AI work store backed by durable offline snapshots.
    public init(offlineStore: OfflineStore) {
        self.offlineStore = offlineStore
    }

    /// Saves or replaces a local AI work snapshot.
    public func save(_ snapshot: AIWorkSnapshot) {
        offlineStore.set(
            key: CacheKeys.aiWork(capability: snapshot.capability, id: snapshot.id),
            entityType: Self.entityType,
            value: snapshot,
            lastSyncAt: nil
        )
    }

    /// Loads a local AI work snapshot for the exact capability and ID.
    public func load(id: UUID, capability: IntelligenceCapability) -> AIWorkSnapshot? {
        offlineStore.get(key: CacheKeys.aiWork(capability: capability, id: id), as: AIWorkSnapshot.self)
    }

    /// Removes a local AI work snapshot for the exact capability and ID.
    public func remove(id: UUID, capability: IntelligenceCapability) {
        offlineStore.remove(key: CacheKeys.aiWork(capability: capability, id: id))
    }
}

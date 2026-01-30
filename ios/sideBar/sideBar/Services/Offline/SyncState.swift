import Foundation

/// Represents sync status for an entity shown in the UI.
public enum SyncState: String, Codable {
    case synced
    case pending
    case conflict
}

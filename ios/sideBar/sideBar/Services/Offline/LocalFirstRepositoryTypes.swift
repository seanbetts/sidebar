import Foundation

enum ItemSyncState: Equatable, Sendable {
    case synced
    case localOnly
    case queued
    case syncing
    case failed(message: String?)
}

enum DetailAvailabilityState: Equatable, Sendable {
    case available
    case loading
    case unavailableOffline
    case loadFailed(message: String)
}

enum LocalFirstDetailSource: Equatable, Sendable {
    case localSnapshot
    case remote
}

struct LocalFirstDetailState<Value> {
    let value: Value?
    let availability: DetailAvailabilityState
    let source: LocalFirstDetailSource?
}

extension LocalFirstDetailState: Equatable where Value: Equatable {}

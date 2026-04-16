import Foundation

@MainActor
final class LocalFirstRepository<Value> {
    typealias CapabilityPolicyProvider = @MainActor () -> OfflineCapabilityPolicy
    typealias LocalLoader = @MainActor (String) -> Value?
    typealias RemoteLoader = @MainActor (String) async throws -> Value
    typealias RemotePersistence = @MainActor (String, Value) -> Void

    private let capabilityPolicy: CapabilityPolicyProvider
    private let loadLocal: LocalLoader
    private let loadRemote: RemoteLoader
    private let persistRemote: RemotePersistence?

    init(
        capabilityPolicy: @escaping CapabilityPolicyProvider,
        loadLocal: @escaping LocalLoader,
        loadRemote: @escaping RemoteLoader,
        persistRemote: RemotePersistence? = nil
    ) {
        self.capabilityPolicy = capabilityPolicy
        self.loadLocal = loadLocal
        self.loadRemote = loadRemote
        self.persistRemote = persistRemote
    }

    func loadDetail(id: String, force: Bool = false) async -> LocalFirstDetailState<Value> {
        if !force, let local = loadLocal(id) {
            return LocalFirstDetailState(
                value: local,
                availability: .available,
                source: .localSnapshot
            )
        }

        guard capabilityPolicy().canAttemptServerRead else {
            return LocalFirstDetailState(
                value: nil,
                availability: .unavailableOffline,
                source: nil
            )
        }

        do {
            let remote = try await loadRemote(id)
            persistRemote?(id, remote)
            return LocalFirstDetailState(
                value: remote,
                availability: .available,
                source: .remote
            )
        } catch {
            return LocalFirstDetailState(
                value: nil,
                availability: .loadFailed(message: error.localizedDescription),
                source: nil
            )
        }
    }
}

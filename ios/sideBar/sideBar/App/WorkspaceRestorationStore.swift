import Foundation

public final class WorkspaceRestorationStore {
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private struct DueTodayAutoOpenMarker: Codable, Equatable {
        let userId: String?
        let localDateKey: String
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ snapshot: DeviceWorkspaceSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        userDefaults.set(data, forKey: key(for: snapshot.family))
    }

    func load(
        family: DeviceWorkspaceFamily,
        expectedUserId: String?
    ) -> DeviceWorkspaceSnapshot? {
        guard let data = userDefaults.data(forKey: key(for: family)),
              let snapshot = try? decoder.decode(DeviceWorkspaceSnapshot.self, from: data),
              snapshot.family == family,
              snapshot.isCurrentSchema,
              snapshot.userId == expectedUserId else {
            return nil
        }
        return snapshot
    }

    func clear(family: DeviceWorkspaceFamily) {
        userDefaults.removeObject(forKey: key(for: family))
    }

    func clearAll() {
        clear(family: .phone)
        clear(family: .workspace)
        userDefaults.removeObject(forKey: AppStorageKeys.workspaceRestorationDueTodayAutoOpenDate)
    }

    func recordDueTodayAutoOpen(userId: String?, localDateKey: String) {
        let marker = DueTodayAutoOpenMarker(
            userId: userId,
            localDateKey: localDateKey
        )
        guard let data = try? encoder.encode(marker) else { return }
        userDefaults.set(data, forKey: AppStorageKeys.workspaceRestorationDueTodayAutoOpenDate)
    }

    func hasDueTodayAutoOpened(userId: String?, localDateKey: String) -> Bool {
        guard let data = userDefaults.data(
            forKey: AppStorageKeys.workspaceRestorationDueTodayAutoOpenDate
        ),
              let marker = try? decoder.decode(DueTodayAutoOpenMarker.self, from: data) else {
            return false
        }
        return marker.userId == userId && marker.localDateKey == localDateKey
    }

    private func key(for family: DeviceWorkspaceFamily) -> String {
        switch family {
        case .phone:
            return AppStorageKeys.workspaceRestorationPhone
        case .workspace:
            return AppStorageKeys.workspaceRestorationWorkspace
        }
    }
}

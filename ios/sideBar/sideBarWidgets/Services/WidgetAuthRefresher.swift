import Foundation
import sideBarShared

protocol WidgetAuthRefreshing {
    func ensureValidSession(forceRefresh: Bool) async -> Bool
}

final class WidgetAuthRefresher: WidgetAuthRefreshing {
    private let refresher: ExtensionAuthSessionRefresher

    init?(keychain: KeychainAuthStateStore, bundle: Bundle = .main) {
        guard let refresher = ExtensionAuthSessionRefresher(keychain: keychain, bundle: bundle) else {
            return nil
        }
        self.refresher = refresher
    }

    func ensureValidSession(forceRefresh: Bool = false) async -> Bool {
        await refresher.ensureValidSession(forceRefresh: forceRefresh)
    }

    static func shouldRefreshAccessToken(
        _ accessToken: String,
        now: Date = Date(),
        leadTime: TimeInterval
    ) -> Bool {
        ExtensionAuthSessionRefresher.shouldRefreshAccessToken(
            accessToken,
            now: now,
            leadTime: leadTime
        )
    }
}

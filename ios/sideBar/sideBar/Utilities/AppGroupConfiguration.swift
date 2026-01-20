import Foundation

public enum AppGroupConfiguration {
    private static let appGroupIdKey = "APP_GROUP_ID"
    private static let keychainAccessGroupKey = "KEYCHAIN_ACCESS_GROUP"
    private static let keychainServiceKey = "KEYCHAIN_SERVICE"

    public static var appGroupId: String? {
        if let configured = loadString(forKey: appGroupIdKey) {
            return configured
        }
        guard let bundleId = Bundle.main.bundleIdentifier else { return nil }
        let normalized = bundleId.replacingOccurrences(of: ".ShareExtension", with: "")
        return "group.\(normalized)"
    }

    public static var keychainAccessGroup: String? {
        loadString(forKey: keychainAccessGroupKey)
    }

    public static var keychainService: String? {
        loadString(forKey: keychainServiceKey)
    }

    private static func loadString(forKey key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        if trimmed.contains("$(") {
            return nil
        }
        return trimmed
    }
}

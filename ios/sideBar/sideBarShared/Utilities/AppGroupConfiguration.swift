import Foundation

/// Provides app group, keychain access group, and shared container identifiers.
public enum AppGroupConfiguration {
    private static let appGroupIdKey = "APP_GROUP_ID"
    private static let keychainAccessGroupKey = "KEYCHAIN_ACCESS_GROUP"
    private static let keychainServiceKey = "KEYCHAIN_SERVICE"
    private static let sharedBundleSuffixes = [
        ".sideBar-Safari-Extension--macOS-.Extension",
        ".sideBar-Safari-Extension--macOS-",
        ".sideBar-Safari-Extension",
        ".sideBarWidgets",
        ".ShareExtension"
    ]

    public static var appGroupId: String? {
        resolvedAppGroupId()
    }

    public static var keychainAccessGroup: String? {
        loadString(forKey: keychainAccessGroupKey)
    }

    public static var keychainService: String? {
        loadString(forKey: keychainServiceKey)
    }

    public static func resolvedAppGroupId(
        configuredValue: String? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> String? {
        if let configured = normalizedConfiguredValue(configuredValue) {
            return configured
        }
        guard let normalized = normalizedSharedBundleIdentifier(bundleIdentifier) else { return nil }
        return "group.\(normalized)"
    }

    public static func normalizedSharedBundleIdentifier(_ bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return sharedBundleSuffixes.reduce(trimmed) { partial, suffix in
            partial.replacingOccurrences(of: suffix, with: "")
        }
    }

    private static func loadString(forKey key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return normalizedConfiguredValue(value)
    }

    private static func normalizedConfiguredValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        if trimmed.contains("$(") {
            return nil
        }
        return trimmed
    }
}

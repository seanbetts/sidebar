import Foundation

/// Builds the app-version HTTP header shared by app and extension requests.
public enum AppVersionHeader {
    /// Header name used for app-version request metadata.
    public static let fieldName = "X-App-Version"

    /// Returns the current bundle version value formatted for request headers.
    public static func currentValue(bundle: Bundle = .main) -> String? {
        let shortVersion = (
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = (
            bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let shortVersion, !shortVersion.isEmpty,
           let buildVersion, !buildVersion.isEmpty {
            return "\(shortVersion) (\(buildVersion))"
        }
        if let shortVersion, !shortVersion.isEmpty {
            return shortVersion
        }
        if let buildVersion, !buildVersion.isEmpty {
            return buildVersion
        }
        return nil
    }
}

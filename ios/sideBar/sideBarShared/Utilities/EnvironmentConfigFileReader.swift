import Foundation

public enum EnvironmentConfigFileReader {
    public static func loadString(forKey key: String, bundle: Bundle = .main) -> String? {
        if let url = bundle.url(forResource: "SideBarConfig", withExtension: "plist") {
            return loadString(forKey: key, url: url)
        }

        let fallbackUrl = bundle.bundleURL.appendingPathComponent("SideBarConfig.plist")
        if FileManager.default.fileExists(atPath: fallbackUrl.path) {
            return loadString(forKey: key, url: fallbackUrl)
        }

        return nil
    }

    public static func loadString(forKey key: String, url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }
        guard let rawValue = plist[key] as? String else {
            return nil
        }
        let value = rawValue.trimmed
        return value.isEmpty ? nil : value
    }
}

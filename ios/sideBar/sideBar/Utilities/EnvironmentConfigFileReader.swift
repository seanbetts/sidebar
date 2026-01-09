import Foundation

public enum EnvironmentConfigFileReader {
    public static func loadString(forKey key: String, bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "SideBarConfig", withExtension: "plist") else {
            return nil
        }
        return loadString(forKey: key, url: url)
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
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

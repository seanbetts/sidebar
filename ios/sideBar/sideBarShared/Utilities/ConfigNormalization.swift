import Foundation

public enum ConfigNormalization {
    public static func normalizeConfigValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") {
            return nil
        }
        if trimmed.hasPrefix("${") && trimmed.hasSuffix("}") {
            return nil
        }
        return trimmed.replacingOccurrences(of: "\\/", with: "/")
    }

    public static func parseHTTPURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }
}

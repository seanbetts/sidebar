import Foundation

public enum LogRedaction {
    public static func redactedURLString(_ url: URL?) -> String {
        guard let url else { return "nil" }
        guard let scheme = url.scheme, !scheme.isEmpty else { return "invalid-url" }

        if let host = rawHost(for: url), !host.isEmpty {
            guard isSafeHost(host) else { return "invalid-url" }
            var result = "\(scheme)://\(host)"
            if let port = url.port {
                result += ":\(port)"
            }
            return result
        }

        return "\(scheme)://redacted"
    }

    public static func redactedURLString(_ rawValue: String?) -> String {
        guard let rawValue, !rawValue.isEmpty else { return "nil" }
        guard let url = URL(string: rawValue), url.scheme != nil else {
            return "invalid-url"
        }
        return redactedURLString(url)
    }

    public static func safariPayloadSummary(action: String?, urlString: String?) -> String {
        let resolvedAction = action?.isEmpty == false ? action ?? "nil" : "nil"
        let hasURL = urlString?.isEmpty == false
        return "action=\(resolvedAction) has_url=\(hasURL ? "true" : "false")"
    }

    private static func rawHost(for url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedHost ?? url.host
    }

    private static func isSafeHost(_ host: String) -> Bool {
        guard containsUnsafeHostDelimiter(host) == false else { return false }
        guard let decodedHost = host.removingPercentEncoding else { return true }
        return containsUnsafeHostDelimiter(decodedHost) == false
    }

    private static func containsUnsafeHostDelimiter(_ value: String) -> Bool {
        value.contains { character in
            character == "/" ||
                character == "?" ||
                character == "#" ||
                character == "@" ||
                character == "\\"
        }
    }
}

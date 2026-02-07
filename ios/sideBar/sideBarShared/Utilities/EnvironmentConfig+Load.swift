import Foundation

public enum EnvironmentConfigLoadError: LocalizedError, Equatable {
    case missingValue(key: String)
    case invalidUrl(key: String, value: String)

    public var errorDescription: String? {
        switch self {
        case let .missingValue(key):
            return "Missing required configuration value: \(key)"
        case let .invalidUrl(key, value):
            return "Invalid URL for \(key): \(value)"
        }
    }
}

public extension EnvironmentConfig {
    static func load() throws -> EnvironmentConfig {
        let apiBaseUrlString = defaultApiBaseUrlString()
        let supabaseUrlString = try loadString(key: "SUPABASE_URL")
        let supabaseAnonKey = try loadString(key: "SUPABASE_ANON_KEY")
        let r2EndpointString = loadOptionalString(key: "R2_ENDPOINT")
        let r2FaviconBucket = loadOptionalString(key: "R2_FAVICON_BUCKET")
        let r2FaviconPublicBaseUrlString = loadOptionalString(
            key: "R2_FAVICON_PUBLIC_BASE_URL"
        )

        let apiBaseUrl = try parseHttpUrl(key: "API_BASE_URL", value: apiBaseUrlString)
        let supabaseUrl = try parseHttpUrl(key: "SUPABASE_URL", value: supabaseUrlString)

        var r2Endpoint: URL?
        if let r2EndpointString {
            r2Endpoint = try parseHttpUrl(key: "R2_ENDPOINT", value: r2EndpointString)
        }

        var r2FaviconPublicBaseUrl: URL?
        if let r2FaviconPublicBaseUrlString {
            r2FaviconPublicBaseUrl = try parseHttpUrl(
                key: "R2_FAVICON_PUBLIC_BASE_URL",
                value: r2FaviconPublicBaseUrlString
            )
        }

        return EnvironmentConfig(
            apiBaseUrl: apiBaseUrl,
            supabaseUrl: supabaseUrl,
            supabaseAnonKey: supabaseAnonKey,
            r2Endpoint: r2Endpoint,
            r2FaviconBucket: r2FaviconBucket,
            r2FaviconPublicBaseUrl: r2FaviconPublicBaseUrl
        )
    }

    static func isRunningTestsOrPreviews() -> Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        return false
    }
}

private func defaultApiBaseUrlString() -> String {
    if let override = loadOptionalString(key: "API_BASE_URL") {
        return override
    }
    #if targetEnvironment(simulator)
    return "http://127.0.0.1:8001/api/v1"
    #else
    return "https://sidebar-api.fly.dev/api/v1"
    #endif
}

private func loadString(key: String) throws -> String {
    if let value = loadOptionalString(key: key) {
        return value
    }
    throw EnvironmentConfigLoadError.missingValue(key: key)
}

private func loadOptionalString(key: String) -> String? {
    if let value = ProcessInfo.processInfo.environment[key],
        let normalized = normalizeLoadedValue(value) {
        return normalized
    }

    if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
        let normalized = normalizeLoadedValue(value) {
        return normalized
    }

    if let value = EnvironmentConfigFileReader.loadString(forKey: key),
        let normalized = normalizeLoadedValue(value) {
        return normalized
    }

    return nil
}

private func parseHttpUrl(key: String, value: String) throws -> URL {
    guard
        let url = URL(string: value),
        let scheme = url.scheme?.lowercased(),
        (scheme == "http" || scheme == "https"),
        let host = url.host,
        !host.isEmpty
    else {
        throw EnvironmentConfigLoadError.invalidUrl(key: key, value: value)
    }
    return url
}

private func normalizeLoadedValue(_ value: String) -> String? {
    let trimmed = value.trimmed
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") {
        return nil
    }
    if trimmed.hasPrefix("${") && trimmed.hasSuffix("}") {
        return nil
    }
    return decodeEscapedConfigString(trimmed)
}

private func decodeEscapedConfigString(_ value: String) -> String {
    // Values coming from .xcconfig often escape URL slashes as `\/`.
    value.replacingOccurrences(of: "\\/", with: "/")
}

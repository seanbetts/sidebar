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
        let r2Bucket = loadOptionalString(key: "R2_BUCKET")

        guard let apiBaseUrl = URL(string: apiBaseUrlString) else {
            throw EnvironmentConfigLoadError.invalidUrl(key: "API_BASE_URL", value: apiBaseUrlString)
        }

        guard let supabaseUrl = URL(string: supabaseUrlString) else {
            throw EnvironmentConfigLoadError.invalidUrl(key: "SUPABASE_URL", value: supabaseUrlString)
        }

        var r2Endpoint: URL?
        if let r2EndpointString {
            guard let url = URL(string: r2EndpointString) else {
                throw EnvironmentConfigLoadError.invalidUrl(
                    key: "R2_ENDPOINT",
                    value: r2EndpointString
                )
            }
            r2Endpoint = url
        }

        return EnvironmentConfig(
            apiBaseUrl: apiBaseUrl,
            supabaseUrl: supabaseUrl,
            supabaseAnonKey: supabaseAnonKey,
            r2Endpoint: r2Endpoint,
            r2Bucket: r2Bucket
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
    #if targetEnvironment(simulator)
    return "http://127.0.0.1:8001/api/v1"
    #else
    if let override = loadOptionalString(key: "API_BASE_URL") {
        return override
    }
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
    if let value = ProcessInfo.processInfo.environment[key], !value.trimmed.isEmpty {
        return value.trimmed
    }

    if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
        !value.trimmed.isEmpty {
        return value.trimmed
    }

    if let value = EnvironmentConfigFileReader.loadString(forKey: key) {
        return value
    }

    return nil
}

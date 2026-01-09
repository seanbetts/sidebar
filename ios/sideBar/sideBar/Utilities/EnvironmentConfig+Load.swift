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
        let apiBaseUrlString = try loadString(key: "API_BASE_URL")
        let supabaseUrlString = try loadString(key: "SUPABASE_URL")
        let supabaseAnonKey = try loadString(key: "SUPABASE_ANON_KEY")

        guard let apiBaseUrl = URL(string: apiBaseUrlString) else {
            throw EnvironmentConfigLoadError.invalidUrl(key: "API_BASE_URL", value: apiBaseUrlString)
        }

        guard let supabaseUrl = URL(string: supabaseUrlString) else {
            throw EnvironmentConfigLoadError.invalidUrl(key: "SUPABASE_URL", value: supabaseUrlString)
        }

        return EnvironmentConfig(
            apiBaseUrl: apiBaseUrl,
            supabaseUrl: supabaseUrl,
            supabaseAnonKey: supabaseAnonKey
        )
    }
}

private func loadString(key: String) throws -> String {
    if let value = ProcessInfo.processInfo.environment[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    throw EnvironmentConfigLoadError.missingValue(key: key)
}

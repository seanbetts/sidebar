import Foundation

public struct EnvironmentConfig {
    public let apiBaseUrl: URL
    public let supabaseUrl: URL
    public let supabaseAnonKey: String

    public init(apiBaseUrl: URL, supabaseUrl: URL, supabaseAnonKey: String) {
        self.apiBaseUrl = apiBaseUrl
        self.supabaseUrl = supabaseUrl
        self.supabaseAnonKey = supabaseAnonKey
    }

    public static func fallbackForTesting() -> EnvironmentConfig {
        EnvironmentConfig(
            apiBaseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            supabaseUrl: URL(string: "http://localhost")!,
            supabaseAnonKey: "test"
        )
    }
}

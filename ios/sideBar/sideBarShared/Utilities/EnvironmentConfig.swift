import Foundation

public struct EnvironmentConfig {
    public let apiBaseUrl: URL
    public let supabaseUrl: URL
    public let supabaseAnonKey: String
    public let r2Endpoint: URL?

    public init(
        apiBaseUrl: URL,
        supabaseUrl: URL,
        supabaseAnonKey: String,
        r2Endpoint: URL? = nil
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.supabaseUrl = supabaseUrl
        self.supabaseAnonKey = supabaseAnonKey
        self.r2Endpoint = r2Endpoint
    }

    public static func fallbackForTesting() -> EnvironmentConfig {
        EnvironmentConfig(
            apiBaseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            supabaseUrl: URL(string: "http://localhost")!,
            supabaseAnonKey: "test",
            r2Endpoint: nil
        )
    }
}

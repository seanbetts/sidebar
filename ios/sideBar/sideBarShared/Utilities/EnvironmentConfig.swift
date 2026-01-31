import Foundation

public struct EnvironmentConfig {
    public let apiBaseUrl: URL
    public let supabaseUrl: URL
    public let supabaseAnonKey: String
    public let r2Endpoint: URL?
    public let r2FaviconBucket: String?
    public let r2FaviconPublicBaseUrl: URL?

    public init(
        apiBaseUrl: URL,
        supabaseUrl: URL,
        supabaseAnonKey: String,
        r2Endpoint: URL? = nil,
        r2FaviconBucket: String? = nil,
        r2FaviconPublicBaseUrl: URL? = nil
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.supabaseUrl = supabaseUrl
        self.supabaseAnonKey = supabaseAnonKey
        self.r2Endpoint = r2Endpoint
        self.r2FaviconBucket = r2FaviconBucket
        self.r2FaviconPublicBaseUrl = r2FaviconPublicBaseUrl
    }

    public static func fallbackForTesting() -> EnvironmentConfig {
        EnvironmentConfig(
            apiBaseUrl: URL(string: "http://127.0.0.1:8001/api/v1")!,
            supabaseUrl: URL(string: "http://localhost")!,
            supabaseAnonKey: "test",
            r2Endpoint: nil,
            r2FaviconBucket: nil,
            r2FaviconPublicBaseUrl: nil
        )
    }
}

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
}

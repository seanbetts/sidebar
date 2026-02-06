import XCTest
import sideBarShared
@testable import sideBar

final class EnvironmentConfigLoadTests: XCTestCase {
    func testLoadPrefersApiBaseUrlOverrideFromEnvironment() throws {
        let originalAPI = environmentValue(for: "API_BASE_URL")
        let originalSupabaseURL = environmentValue(for: "SUPABASE_URL")
        let originalSupabaseAnon = environmentValue(for: "SUPABASE_ANON_KEY")

        setEnvironmentValue("https://api.example.com/api/v1", for: "API_BASE_URL")
        setEnvironmentValue("https://project.supabase.co", for: "SUPABASE_URL")
        setEnvironmentValue("anon-key", for: "SUPABASE_ANON_KEY")
        defer {
            setEnvironmentValue(originalAPI, for: "API_BASE_URL")
            setEnvironmentValue(originalSupabaseURL, for: "SUPABASE_URL")
            setEnvironmentValue(originalSupabaseAnon, for: "SUPABASE_ANON_KEY")
        }

        let config = try EnvironmentConfig.load()
        XCTAssertEqual(config.apiBaseUrl.absoluteString, "https://api.example.com/api/v1")
    }

    private func environmentValue(for key: String) -> String? {
        guard let cString = getenv(key) else { return nil }
        return String(cString: cString)
    }

    private func setEnvironmentValue(_ value: String?, for key: String) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}

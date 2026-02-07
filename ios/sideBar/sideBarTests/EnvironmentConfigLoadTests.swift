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

    func testLoadRejectsSupabaseUrlWithoutHost() {
        let originalAPI = environmentValue(for: "API_BASE_URL")
        let originalSupabaseURL = environmentValue(for: "SUPABASE_URL")
        let originalSupabaseAnon = environmentValue(for: "SUPABASE_ANON_KEY")

        setEnvironmentValue("https://api.example.com/api/v1", for: "API_BASE_URL")
        setEnvironmentValue("https:/missing-host", for: "SUPABASE_URL")
        setEnvironmentValue("anon-key", for: "SUPABASE_ANON_KEY")
        defer {
            setEnvironmentValue(originalAPI, for: "API_BASE_URL")
            setEnvironmentValue(originalSupabaseURL, for: "SUPABASE_URL")
            setEnvironmentValue(originalSupabaseAnon, for: "SUPABASE_ANON_KEY")
        }

        XCTAssertThrowsError(try EnvironmentConfig.load()) { error in
            XCTAssertEqual(
                error as? EnvironmentConfigLoadError,
                .invalidUrl(key: "SUPABASE_URL", value: "https:/missing-host")
            )
        }
    }

    func testLoadAcceptsEscapedUrlsFromEnvironment() throws {
        let originalAPI = environmentValue(for: "API_BASE_URL")
        let originalSupabaseURL = environmentValue(for: "SUPABASE_URL")
        let originalSupabaseAnon = environmentValue(for: "SUPABASE_ANON_KEY")

        setEnvironmentValue("http:\\/\\/127.0.0.1:8001\\/api\\/v1", for: "API_BASE_URL")
        setEnvironmentValue("https:\\/\\/project.supabase.co", for: "SUPABASE_URL")
        setEnvironmentValue("anon-key", for: "SUPABASE_ANON_KEY")
        defer {
            setEnvironmentValue(originalAPI, for: "API_BASE_URL")
            setEnvironmentValue(originalSupabaseURL, for: "SUPABASE_URL")
            setEnvironmentValue(originalSupabaseAnon, for: "SUPABASE_ANON_KEY")
        }

        let config = try EnvironmentConfig.load()
        XCTAssertEqual(config.apiBaseUrl.absoluteString, "http://127.0.0.1:8001/api/v1")
        XCTAssertEqual(config.supabaseUrl.absoluteString, "https://project.supabase.co")
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

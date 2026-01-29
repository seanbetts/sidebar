import XCTest
import sideBarShared
@testable import sideBar

final class EnvironmentConfigFileReaderTests: XCTestCase {
    func testLoadStringFromPlist() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SideBarConfigTest.plist")
        let payload: [String: String] = [
            "API_BASE_URL": "http://localhost:8001",
            "SUPABASE_URL": "https://example.supabase.co",
            "SUPABASE_ANON_KEY": "anon-key"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(EnvironmentConfigFileReader.loadString(forKey: "API_BASE_URL", url: url), "http://localhost:8001")
        XCTAssertEqual(EnvironmentConfigFileReader.loadString(forKey: "SUPABASE_URL", url: url), "https://example.supabase.co")
        XCTAssertEqual(EnvironmentConfigFileReader.loadString(forKey: "SUPABASE_ANON_KEY", url: url), "anon-key")
        XCTAssertNil(EnvironmentConfigFileReader.loadString(forKey: "MISSING_KEY", url: url))
    }
}

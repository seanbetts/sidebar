import XCTest

final class URLSchemeConfigurationSourceTests: XCTestCase {
    func testLogicHostDoesNotRegisterSidebarURLScheme() throws {
        let source = try projectSource()

        XCTAssertFalse(source.contains("CFBundleURLName = \"ai.sidebar.sidebar.logic-host\";"))
        XCTAssertTrue(source.contains("PRODUCT_BUNDLE_IDENTIFIER = \"ai.sidebar.sidebar.logic-host\";"))
    }

    private func projectSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let projectURL = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sideBar.xcodeproj")
            .appendingPathComponent("project.pbxproj")

        do {
            return try String(contentsOf: projectURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read Xcode project source: \(error)", file: file, line: line)
            throw error
        }
    }
}

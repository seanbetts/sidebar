import XCTest

final class WebsitesViewSourceTests: XCTestCase {
    func testWebsitesViewDoesNotOwnLifecycleRefresh() throws {
        let normalized = try websitesViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("@Environment(\\.scenePhase)"))
        XCTAssertFalse(normalized.contains("scenePhase==.active"))
        XCTAssertFalse(normalized.contains(".onChange(of:scenePhase)"))
        XCTAssertFalse(normalized.contains(".task{awaitenvironment.websitesViewModel.load(force:true)}"))
        XCTAssertFalse(normalized.contains(".task{awaitenvironment.websitesViewModel.refreshFromExtension()}"))
        XCTAssertFalse(normalized.contains("awaitenvironment.websitesViewModel.load(force:true)"))
    }

    private func websitesViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Websites")
            .appendingPathComponent("WebsitesView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read WebsitesView.swift: \(error)", file: file, line: line)
            throw error
        }
    }
}

import XCTest

final class AppEnvironmentTaskBadgeSourceTests: XCTestCase {
    func testTaskBadgeUpdatesUseSharedBadgeUpdaterInsteadOfIOsOnlyBadgePath() throws {
        let normalized = try taskBadgeUpdatesSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Self.taskBadgeCount(authState:authState,counts:counts)"))
        XCTAssertTrue(normalized.contains("self.storage.taskBadgeUpdater.update(count:badgeCount)"))
        XCTAssertFalse(normalized.contains("UNUserNotificationCenter.current().setBadgeCount"))
        XCTAssertFalse(normalized.contains("#ifos(iOS)"))
    }

    private func taskBadgeUpdatesSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let source = try appEnvironmentSetupSource(file: file, line: line)
        guard let start = source.range(of: "private func setupTaskBadgeUpdates()"),
              let end = source.range(of: "nonisolated static func taskBadgeCount") else {
            XCTFail("Failed to locate task badge update source", file: file, line: line)
            throw NSError(domain: "AppEnvironmentTaskBadgeSourceTests", code: 1)
        }

        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func appEnvironmentSetupSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("App")
            .appendingPathComponent("AppEnvironment+Setup.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read AppEnvironment+Setup.swift: \(error)", file: file, line: line)
            throw error
        }
    }
}

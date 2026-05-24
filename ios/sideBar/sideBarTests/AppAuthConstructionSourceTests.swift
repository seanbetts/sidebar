import XCTest

final class AppAuthConstructionSourceTests: XCTestCase {
    func testSideBarAppBuildsAuthThroughProductSessionFactory() throws {
        let normalized = try sideBarAppSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("DefaultAuthSessionFactory().makeAuthSession("))
        XCTAssertFalse(normalized.contains("SupabaseAuthAdapter("))
        XCTAssertFalse(normalized.contains("KeychainAuthStateStore("))
    }

    func testUITestAuthBootstrapIsDebugGatedInSideBarApp() throws {
        let source = try sideBarAppSource()
        let normalized = source.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("#ifDEBUGletseededSession=UITestAuthBootstrap.makeSeededSession"))
        XCTAssertTrue(normalized.contains("#ifDEBUGletinitialPasswordResetState:PasswordResetState?="))
    }
}

private func sideBarAppSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("sideBarApp.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read sideBarApp.swift: \(error)", file: file, line: line)
        throw error
    }
}

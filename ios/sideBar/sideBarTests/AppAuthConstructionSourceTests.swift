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

    func testLegacyNetworkMonitorSourceIsRemoved() throws {
        let fileURL = URL(fileURLWithPath: "\(#filePath)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("App")
            .appendingPathComponent("NetworkMonitor.swift")

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testAppleUILiveBackendCoverageStaysQuarantined() throws {
        let uiTests = try source(at: ["sideBarUITests", "sideBarUITests.swift"])
        let uiHelpers = try source(at: ["sideBarUITests", "sideBarUITests+Helpers.swift"])

        let defaultLiveCalls = uiTests.components(
            separatedBy: "try requireLiveUITestsEnabled()"
        ).count - 1

        XCTAssertEqual(defaultLiveCalls, 1)
        XCTAssertTrue(uiTests.contains("func testLoginSuccessNavigatesToSignedInHome()"))
        XCTAssertTrue(uiTests.contains("func testLocalAuthenticatedLaunchShowsSignedInHome()"))
        XCTAssertTrue(uiHelpers.contains("func requireExtendedLiveUITestsEnabled()"))
        XCTAssertTrue(uiHelpers.contains("let app = launchLocallyAuthenticatedApp()"))
    }
}

private func sideBarAppSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try source(at: ["sideBar", "sideBarApp.swift"], file: file, line: line)
}

private func source(
    at components: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    var sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    for component in components {
        sourceURL.appendPathComponent(component)
    }

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(sourceURL.lastPathComponent): \(error)", file: file, line: line)
        throw error
    }
}

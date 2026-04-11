import XCTest

final class MacWebsiteQueueBackgroundHostTests: XCTestCase {
    func testMacAppDelegateRequestsWebsiteQueueBootstrapDuringStartup() throws {
        let normalized = try macAppDelegateSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("requestWebsiteQueueBootstrapIfPossible()"))
    }

    func testMacAppDelegateQueuesWebsiteQueueBootstrapUntilEnvironmentIsReady() throws {
        let normalized = try macAppDelegateSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("privatestaticvarshouldBootstrapWebsiteQueueWhenEnvironmentReady=false"))
        XCTAssertTrue(normalized.contains("staticfuncrequestWebsiteQueueBootstrapIfPossible(){"))
        XCTAssertTrue(normalized.contains("ifletenvironment=AppEnvironment.shared{"))
        XCTAssertTrue(normalized.contains("environment.bootstrapMacWindowlessWebsiteQueueHost()"))
        XCTAssertTrue(normalized.contains("shouldBootstrapWebsiteQueueWhenEnvironmentReady=true"))
        XCTAssertTrue(normalized.contains("staticfuncflushQueuedWebsiteQueueBootstrap(usingenvironment:AppEnvironment){"))
        XCTAssertTrue(normalized.contains("guardshouldBootstrapWebsiteQueueWhenEnvironmentReadyelse{return}"))
        XCTAssertTrue(normalized.contains("shouldBootstrapWebsiteQueueWhenEnvironmentReady=false"))
        XCTAssertTrue(normalized.contains("environment.bootstrapMacWindowlessWebsiteQueueHost()"))
    }

    func testAppEnvironmentFlushesQueuedMacWebsiteQueueBootstrapWhenReady() throws {
        let normalized = try appEnvironmentSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("#elseifos(macOS)"))
        XCTAssertTrue(normalized.contains("MacAppDelegate.flushQueuedDeepLinks(using:self)"))
        XCTAssertTrue(normalized.contains("MacAppDelegate.flushQueuedWebsiteQueueBootstrap(using:self)"))
    }

    private func macAppDelegateSource() throws -> String {
        try source(named: "MacAppDelegate.swift")
    }

    private func appEnvironmentSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sideBar")
            .appendingPathComponent("App")
            .appendingPathComponent("AppEnvironment.swift")
        do {
            return try String(contentsOf: url)
        } catch {
            XCTFail("Failed to read AppEnvironment.swift: \(error)")
            throw error
        }
    }

    private func source(named fileName: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sideBar")
            .appendingPathComponent("App")
            .appendingPathComponent(fileName)
        do {
            return try String(contentsOf: url)
        } catch {
            XCTFail("Failed to read \(fileName): \(error)", file: file, line: line)
            throw error
        }
    }
}

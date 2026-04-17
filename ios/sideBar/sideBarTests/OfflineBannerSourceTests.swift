import XCTest

final class OfflineBannerSourceTests: XCTestCase {
    func testOfflineBannerTapRechecksConnectivityBeforePresentingAlert() throws {
        let normalized = try source(named: "Design/Components/OfflineBanner.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("letshouldPresentAlert=awaitenvironment.refreshConnectivityStatusFromBannerTap()"))
        XCTAssertTrue(normalized.contains("guardshouldPresentAlertelse{return}"))
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func source(
    named relativePath: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
    let sourceURL = sideBarRoot.appendingPathComponent(relativePath)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(relativePath): \(error)", file: file, line: line)
        throw error
    }
}

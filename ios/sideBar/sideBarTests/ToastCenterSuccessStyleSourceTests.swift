import XCTest

@testable import sideBar

final class ToastCenterSuccessStyleSourceTests: XCTestCase {
    func testSuccessToastUsesDedicatedSuccessTokens() throws {
        let normalized = try toastCenterSource()

        XCTAssertTrue(normalized.contains("returnDesignTokens.Colors.successBorder"))
    }

    func testSuccessToastDoesNotUseHardcodedContrastBadge() throws {
        let normalized = try toastCenterSource()

        XCTAssertFalse(normalized.contains("case.success:SuccessCheckBadge"))
        XCTAssertFalse(normalized.contains("colorScheme==.dark?.white:.black"))
        XCTAssertFalse(normalized.contains("colorScheme==.dark?.black:.white"))
    }

    func testSuccessTokensAreNotNeutralMutedColors() throws {
        let normalized = try designTokensSource()

        XCTAssertFalse(normalized.contains("staticletsuccess=textPrimary"))
        XCTAssertFalse(normalized.contains("staticletsuccessBackground=muted.opacity(0.55)"))
    }

    private func toastCenterSource() throws -> String {
        try source(named: "ToastCenter.swift")
    }

    private func designTokensSource() throws -> String {
        try source(named: "DesignTokens.swift")
    }

    private func source(named filename: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let matches = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(filename) }
        guard let relativePath = matches.first else {
            throw NSError(domain: "ToastCenterSuccessStyleSourceTests", code: 1)
        }
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

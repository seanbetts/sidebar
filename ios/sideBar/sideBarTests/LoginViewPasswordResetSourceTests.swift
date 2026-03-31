import XCTest

final class LoginViewPasswordResetSourceTests: XCTestCase {
    func testLoginViewIncludesForgotPasswordActionAndConfirmationCopy() throws {
        let normalized = try combinedLoginSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Forgotpassword?"))
        XCTAssertTrue(normalized.contains("Checkyouremailforaresetlinkorcode."))
        XCTAssertTrue(normalized.contains(".frame(maxWidth:.infinity,alignment:.center)"))
        XCTAssertTrue(normalized.contains("DesignTokens.Colors.actionPrimary"))
    }

    private func combinedLoginSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let authRoot = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Auth")
        let sourceURLs = [
            authRoot.appendingPathComponent("LoginView.swift"),
            authRoot.appendingPathComponent("LoginViewComponents.swift")
        ]

        do {
            return try sourceURLs
                .map { try String(contentsOf: $0, encoding: .utf8) }
                .joined(separator: "\n")
        } catch {
            XCTFail("Failed to read auth login sources: \(error)", file: file, line: line)
            throw error
        }
    }
}

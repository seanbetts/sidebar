import XCTest

final class LoginViewPasswordResetSourceTests: XCTestCase {
    func testLoginViewUsesSharedMarketingTaglineInsteadOfLegacyLiteral() throws {
        let normalized = try combinedLoginSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Text(MarketingCopy.tagline)"))
        XCTAssertFalse(normalized.contains("TheAIassisstantthatactuallyknowsyou"))
    }

    func testLoginViewIncludesForgotPasswordActionAndConfirmationCopy() throws {
        let normalized = try combinedLoginSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Forgotpassword?"))
        XCTAssertTrue(normalized.contains("Checkyouremailforaresetlink."))
        XCTAssertTrue(normalized.contains(".frame(maxWidth:.infinity,alignment:.center)"))
        XCTAssertTrue(normalized.contains("DesignTokens.Colors.actionPrimary"))
    }

    func testSignedOutAuthFlowIncludesResetCompletionSurface() throws {
        let normalized = try combinedLoginSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Enteranewpassword"))
        XCTAssertTrue(normalized.contains("Updatepassword"))
        XCTAssertTrue(normalized.contains("Backtosignin"))
        XCTAssertTrue(normalized.contains("FormFieldSecureInput("))
        XCTAssertTrue(normalized.contains("FormField(leadingIcon:AppIcon.Auth.password)"))
        XCTAssertFalse(normalized.contains("SecureFieldWithToggle("))
        XCTAssertTrue(normalized.contains("ForEach(0..<4,id:\\.self)"))
        XCTAssertTrue(normalized.contains("Passwordsdon'tmatch."))
        XCTAssertTrue(normalized.contains("DesignTokens.Colors.border.opacity(0.85)"))
        XCTAssertTrue(normalized.contains("PasswordStrengthRules.guidanceMessage"))
        XCTAssertTrue(normalized.contains(".multilineTextAlignment(.center)"))
        XCTAssertTrue(normalized.contains(".frame(maxWidth:.infinity,minHeight:32,alignment:.center)"))
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
            authRoot.appendingPathComponent("LoginViewComponents.swift"),
            authRoot.appendingPathComponent("PasswordFormValidation.swift"),
            authRoot.appendingPathComponent("PasswordResetCompletionView.swift")
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

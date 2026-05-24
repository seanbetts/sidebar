import XCTest

final class FormFieldAdoptionSourceTests: XCTestCase {
    func testLegacyFormWrapperStructsAreRetired() throws {
        let normalized = try combinedFormSurfaceSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("structProfileIOSFieldRow<Content:View>:View"))
        XCTAssertFalse(normalized.contains("structSettingsMacFieldRow<Content:View>:View"))
        XCTAssertFalse(normalized.contains("structSecureFieldWithToggle<Field:Hashable>:View"))
        XCTAssertFalse(normalized.contains("structLoginFieldRow<Content:View,Trailing:View>:View"))
    }

    func testAuthAndOnboardingCredentialFieldsUseUnifiedFormField() throws {
        let normalized = try combinedFormSurfaceSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("LoginFieldRow("))
        XCTAssertFalse(normalized.contains("SecureFieldWithToggle("))
        XCTAssertFalse(normalized.contains("ProfileIOSFieldRow("))
        XCTAssertFalse(normalized.contains("SettingsMacFieldRow("))

        XCTAssertTrue(normalized.contains("FormField(leadingIcon:AppIcon.Auth.email)"))
        XCTAssertTrue(normalized.contains("FormField(leadingIcon:AppIcon.Auth.password)"))
        XCTAssertTrue(normalized.contains("FormField(leadingIcon:AppIcon.Settings.profile)"))
        XCTAssertTrue(normalized.contains("FormField(leadingIcon:AppIcon.Settings.credentials)"))
        XCTAssertGreaterThanOrEqual(
            normalized.components(separatedBy: "FormFieldSecureInput(").count - 1,
            4
        )
    }
}

private func combinedFormSurfaceSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
    let legacySecureFieldURL = sourceRoot.appendingPathComponent("Views/Auth/SecureFieldWithToggle.swift")
    XCTAssertFalse(
        FileManager.default.fileExists(atPath: legacySecureFieldURL.path),
        "SecureFieldWithToggle.swift should remain removed.",
        file: file,
        line: line
    )
    let sourceURLs = [
        sourceRoot.appendingPathComponent("Design/Components/FormField.swift"),
        sourceRoot.appendingPathComponent("Views/Auth/LoginAuthPresentation.swift"),
        sourceRoot.appendingPathComponent("Views/Auth/LoginView.swift"),
        sourceRoot.appendingPathComponent("Views/Auth/PasswordResetCompletionView.swift"),
        sourceRoot.appendingPathComponent("Views/Onboarding/AddApiKeyStepView.swift"),
        sourceRoot.appendingPathComponent("Views/Onboarding/CreateAccountStepView.swift"),
        sourceRoot.appendingPathComponent("Views/Onboarding/ProfileStepView.swift"),
        sourceRoot.appendingPathComponent("Views/Settings/ProfileIOSFieldRow.swift"),
        sourceRoot.appendingPathComponent("Views/Settings/SettingsMacStyles.swift"),
        sourceRoot.appendingPathComponent("Views/Settings/SettingsPasswordChangeView.swift"),
        sourceRoot.appendingPathComponent("Views/Settings/SettingsSections.swift"),
        sourceRoot.appendingPathComponent("Views/Settings/SettingsSections+SystemMac.swift")
    ]

    do {
        return try sourceURLs
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    } catch {
        XCTFail("Failed to read form field adoption sources: \(error)", file: file, line: line)
        throw error
    }
}

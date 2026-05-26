import XCTest

final class FormFieldAdoptionSourceTests: XCTestCase {
    func testLegacyFormWrapperStructsAreRetired() throws {
        let normalized = try combinedFormSurfaceSource()

        XCTAssertFalse(normalized.contains("structProfileIOSFieldRow<Content:View>:View"))
        XCTAssertFalse(normalized.contains("structSettingsMacFieldRow<Content:View>:View"))
        XCTAssertFalse(normalized.contains("structSecureFieldWithToggle<Field:Hashable>:View"))
        XCTAssertFalse(normalized.contains("structLoginFieldRow<Content:View,Trailing:View>:View"))
    }

    func testAuthAndOnboardingCredentialFieldsUseUnifiedFormField() throws {
        let normalized = try combinedFormSurfaceSource()

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
    StaticSourceGuard.assertFileDoesNotExist(
        at: ["sideBar", "Views", "Auth", "SecureFieldWithToggle.swift"],
        message: "SecureFieldWithToggle.swift should remain removed.",
        file: file,
        line: line
    )
    return try StaticSourceGuard.combinedNormalizedSource(
        at: [
            ["sideBar", "Design", "Components", "FormField.swift"],
            ["sideBar", "Views", "Auth", "LoginAuthPresentation.swift"],
            ["sideBar", "Views", "Auth", "LoginView.swift"],
            ["sideBar", "Views", "Auth", "PasswordResetCompletionView.swift"],
            ["sideBar", "Views", "Onboarding", "AddApiKeyStepView.swift"],
            ["sideBar", "Views", "Onboarding", "CreateAccountStepView.swift"],
            ["sideBar", "Views", "Onboarding", "ProfileStepView.swift"],
            ["sideBar", "Views", "Settings", "ProfileIOSFieldRow.swift"],
            ["sideBar", "Views", "Settings", "SettingsMacStyles.swift"],
            ["sideBar", "Views", "Settings", "SettingsPasswordChangeView.swift"],
            ["sideBar", "Views", "Settings", "SettingsSections.swift"],
            ["sideBar", "Views", "Settings", "SettingsSections+SystemMac.swift"]
        ],
        file: file,
        line: line
    )
}

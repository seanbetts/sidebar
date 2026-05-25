import XCTest

final class AuthOnboardingIconSourceTests: XCTestCase {
    func testAuthAndOnboardingChromeUsesAppIconVocabulary() throws {
        try assertAuthOnboardingVocabularyExists()
        try assertAuthChromeUsesAppIcon()
        try assertOnboardingChromeUsesAppIcon()
        try assertOnboardingLocalModelsExposeAppIcon()
    }

    private func assertAuthOnboardingVocabularyExists() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])

        XCTAssertTrue(appIcon.contains("enumAuth{"))
        XCTAssertTrue(appIcon.contains("publicstaticletemail=AppIcon(rawValue:\"envelope\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletpassword=AppIcon(rawValue:\"lock\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletpasswordLocked=AppIcon(rawValue:\"lock.fill\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletpasswordVisible=AppIcon(rawValue:\"eye.fill\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletpasswordHidden=AppIcon(rawValue:\"eye.slash.fill\")"))

        XCTAssertTrue(appIcon.contains("enumOnboarding{"))
        XCTAssertTrue(appIcon.contains("publicstaticletemailVerification=AppIcon(rawValue:\"envelope.badge\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletassistantBrain=AppIcon(rawValue:\"brain\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletexternalHelp=AppIcon(rawValue:\"arrow.up.right\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletlocationPermission=AppIcon(rawValue:\"location.fill\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletnotificationsPermission=AppIcon(rawValue:\"bell.badge.fill\")"))
    }

    private func assertAuthChromeUsesAppIcon() throws {
        let login = try normalizedSource(at: ["sideBar", "Views", "Auth", "LoginView.swift"])
        let loginComponents = try normalizedSource(at: ["sideBar", "Views", "Auth", "LoginViewComponents.swift"])
        let passwordReset = try normalizedSource(
            at: ["sideBar", "Views", "Auth", "PasswordResetCompletionView.swift"]
        )
        let formField = try normalizedSource(at: ["sideBar", "Design", "Components", "FormField.swift"])

        XCTAssertTrue(login.contains("FormField(leadingIcon:AppIcon.Auth.email)"))
        XCTAssertTrue(login.contains("FormField(leadingIcon:AppIcon.Auth.password)"))
        XCTAssertTrue(login.contains("Image(appIcon:AppIcon.State.warningFilled)"))
        XCTAssertTrue(login.contains("Image(appIcon:AppIcon.Action.clearFilled)"))
        XCTAssertTrue(login.contains("Image(appIcon:AppIcon.Auth.passwordLocked)"))
        XCTAssertFalse(login.contains("leadingSystemName:\"envelope\""))
        XCTAssertFalse(login.contains("leadingSystemName:\"lock\""))
        XCTAssertFalse(login.contains("Image(systemName:\"exclamationmark.triangle.fill\")"))
        XCTAssertFalse(login.contains("Image(systemName:\"xmark.circle.fill\")"))
        XCTAssertFalse(login.contains("Image(systemName:\"lock.fill\")"))

        XCTAssertTrue(loginComponents.contains("Image(appIcon:AppIcon.State.successFilled)"))
        XCTAssertTrue(loginComponents.contains("Image(appIcon:AppIcon.State.offline)"))
        XCTAssertFalse(loginComponents.contains("Image(systemName:\"checkmark.circle.fill\")"))
        XCTAssertFalse(loginComponents.contains("Image(systemName:\"wifi.slash\")"))

        XCTAssertTrue(passwordReset.contains("FormField(leadingIcon:AppIcon.Auth.password)"))
        XCTAssertFalse(passwordReset.contains("leadingSystemName:\"lock\""))

        XCTAssertTrue(formField.contains("caseauth(leadingIcon:AppIcon?)"))
        XCTAssertTrue(formField.contains("Image(appIcon:leadingIcon)"))
        XCTAssertTrue(formField.contains("Image(appIcon:isSecure?AppIcon.Auth.passwordHidden:AppIcon.Auth.passwordVisible)"))
        XCTAssertFalse(formField.contains("Image(systemName:leadingSystemName)"))
        XCTAssertFalse(formField.contains("Image(systemName:isSecure?\"eye.slash.fill\":\"eye.fill\")"))
    }

    private func assertOnboardingChromeUsesAppIcon() throws {
        let onboardingView = try normalizedSource(at: ["sideBar", "Views", "Onboarding", "OnboardingView.swift"])
        let createAccount = try normalizedSource(
            at: ["sideBar", "Views", "Onboarding", "CreateAccountStepView.swift"]
        )
        let verifyEmail = try normalizedSource(at: ["sideBar", "Views", "Onboarding", "VerifyEmailStepView.swift"])
        let profile = try normalizedSource(at: ["sideBar", "Views", "Onboarding", "ProfileStepView.swift"])
        let chooseProvider = try normalizedSource(
            at: ["sideBar", "Views", "Onboarding", "ChooseProviderStepView.swift"]
        )
        let addAPIKey = try normalizedSource(at: ["sideBar", "Views", "Onboarding", "AddApiKeyStepView.swift"])
        let location = try normalizedSource(
            at: ["sideBar", "Views", "Onboarding", "LocationPermissionStepView.swift"]
        )
        let notifications = try normalizedSource(
            at: ["sideBar", "Views", "Onboarding", "NotificationsPermissionStepView.swift"]
        )
        let finalStep = try normalizedSource(at: ["sideBar", "Views", "Onboarding", "FinalStepView.swift"])
        let addKeyBanner = try normalizedSource(at: ["sideBar", "Views", "Chat", "OnboardingAddKeyBanner.swift"])

        XCTAssertTrue(onboardingView.contains("Image(appIcon:AppIcon.Navigation.back)"))
        XCTAssertFalse(onboardingView.contains("Image(systemName:\"chevron.left\")"))

        XCTAssertTrue(createAccount.contains("Image(appIcon:AppIcon.Settings.profile)"))
        XCTAssertFalse(createAccount.contains("Image(systemName:\"person.crop.circle\")"))

        XCTAssertTrue(verifyEmail.contains("Image(appIcon:AppIcon.Onboarding.emailVerification)"))
        XCTAssertTrue(verifyEmail.contains(".accessibilityLabel(\"Verificationcodedigit\\(index+1)\")"))
        XCTAssertFalse(verifyEmail.contains("Image(systemName:\"envelope.badge\")"))

        XCTAssertTrue(profile.contains("Image(appIcon:AppIcon.Settings.profileAdd)"))
        XCTAssertFalse(profile.contains("Image(systemName:\"person.crop.circle.badge.plus\")"))

        XCTAssertTrue(chooseProvider.contains("Image(appIcon:AppIcon.Onboarding.assistantBrain)"))
        XCTAssertTrue(chooseProvider.contains("Image(appIcon:AppIcon.State.success)"))
        XCTAssertFalse(chooseProvider.contains("Image(systemName:\"brain\")"))
        XCTAssertFalse(chooseProvider.contains("Image(systemName:\"checkmark\")"))

        XCTAssertTrue(addAPIKey.contains("Image(appIcon:AppIcon.Settings.credentials)"))
        XCTAssertTrue(addAPIKey.contains("Image(appIcon:AppIcon.Onboarding.externalHelp)"))
        XCTAssertFalse(addAPIKey.contains("Image(systemName:\"key.horizontal\")"))
        XCTAssertFalse(addAPIKey.contains("Image(systemName:\"arrow.up.right\")"))

        XCTAssertTrue(location.contains("Image(appIcon:AppIcon.Onboarding.locationPermission)"))
        XCTAssertFalse(location.contains("Image(systemName:\"location.fill\")"))

        XCTAssertTrue(notifications.contains("Image(appIcon:AppIcon.Onboarding.notificationsPermission)"))
        XCTAssertFalse(notifications.contains("Image(systemName:\"bell.badge.fill\")"))

        XCTAssertTrue(finalStep.contains("Image(appIcon:AppIcon.State.success)"))
        XCTAssertTrue(finalStep.contains("Image(appIcon:AppIcon.State.selectedCircle)"))
        XCTAssertFalse(finalStep.contains("Image(systemName:\"checkmark\")"))
        XCTAssertFalse(finalStep.contains("Image(systemName:\"circle.fill\")"))

        XCTAssertTrue(addKeyBanner.contains("Image(appIcon:AppIcon.Settings.credentialsFilled)"))
        XCTAssertTrue(addKeyBanner.contains("Image(appIcon:AppIcon.Settings.appPreferences)"))
        XCTAssertFalse(addKeyBanner.contains("Image(systemName:\"key.horizontal.fill\")"))
        XCTAssertFalse(addKeyBanner.contains("Image(systemName:\"gearshape\")"))
    }

    private func assertOnboardingLocalModelsExposeAppIcon() throws {
        let discovery = try normalizedSource(at: ["sideBar", "Models", "OnboardingDiscoveryFeature.swift"])
        let featureIntro = try normalizedSource(at: ["sideBar", "Views", "Chat", "FeatureIntroCard.swift"])
        let permissionRecovery = try normalizedSource(
            at: ["sideBar", "ViewModels", "SettingsViewModel+PermissionRecovery.swift"]
        )
        let permissionCard = try normalizedSource(
            at: ["sideBar", "Views", "Onboarding", "OnboardingPermissionCard.swift"]
        )

        XCTAssertTrue(discovery.contains("publicvarappIcon:AppIcon{"))
        XCTAssertTrue(discovery.contains("AppIcon.Domain.notes"))
        XCTAssertTrue(discovery.contains("AppIcon.Domain.tasks"))
        XCTAssertTrue(discovery.contains("AppIcon.Domain.websites"))
        XCTAssertTrue(discovery.contains("AppIcon.Domain.files"))
        XCTAssertTrue(discovery.contains("AppIcon.Domain.skillsStore"))
        XCTAssertFalse(discovery.contains("publicvarsystemImage:String{"))

        XCTAssertTrue(featureIntro.contains("Image(appIcon:feature.appIcon)"))
        XCTAssertFalse(featureIntro.contains("Image(systemName:feature.systemImage)"))

        XCTAssertTrue(permissionRecovery.contains("varappIcon:AppIcon{"))
        XCTAssertTrue(permissionRecovery.contains("AppIcon.Onboarding.locationPermission"))
        XCTAssertTrue(permissionRecovery.contains("AppIcon.Onboarding.notificationsPermission"))
        XCTAssertFalse(permissionRecovery.contains("return\"location.fill\""))
        XCTAssertFalse(permissionRecovery.contains("return\"bell.badge.fill\""))

        XCTAssertTrue(permissionCard.contains("Image(appIcon:item.appIcon)"))
        XCTAssertFalse(permissionCard.contains("Image(systemName:item.systemImage)"))
    }

    private func normalizedSource(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let source = try source(at: pathComponents, file: file, line: line)
        return source.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func source(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = pathComponents.reduce(sideBarRoot) { url, component in
            url.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}

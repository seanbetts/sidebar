import XCTest

final class Task15SettingsIconSourceTests: XCTestCase {
    func testSettingsProfileChromeUsesAppIconVocabulary() throws {
        try assertSettingsVocabularyExists()
        try assertSettingsNavigationChromeUsesAppIcon()
        try assertSettingsProfileFormChromeUsesAppIcon()
    }

    private func assertSettingsVocabularyExists() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])

        XCTAssertTrue(appIcon.contains("publicstaticletskills=AppIcon(rawValue:\"command.circle\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletappPreferences=AppIcon(rawValue:\"gearshape\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletmore=AppIcon(rawValue:\"ellipsis.circle\")"))
    }

    private func assertSettingsNavigationChromeUsesAppIcon() throws {
        let settingsView = try normalizedSource(at: ["sideBar", "Views", "Settings", "SettingsView.swift"])
        let settingsTabs = try normalizedSource(at: ["sideBar", "Views", "Settings", "SettingsView+Tabs.swift"])
        let settingsMore = try normalizedSource(at: ["sideBar", "Views", "Settings", "SettingsMoreTabView.swift"])

        XCTAssertTrue(settingsView.contains("varappIcon:AppIcon{"))
        XCTAssertTrue(
            settingsView.contains(
                "Label(section.displayTitle(assistantDisplayName:viewModel.assistantDisplayName),"
                    + "systemImage:section.appIcon.rawValue)"
            )
        )
        XCTAssertTrue(settingsView.contains("Image(appIcon:AppIcon.Action.clearFilled)"))
        XCTAssertFalse(settingsView.contains("varsystemImage:String{"))
        XCTAssertFalse(settingsView.contains("Image(systemName:\"xmark.circle.fill\")"))

        XCTAssertTrue(settingsTabs.contains("Label(\"Profile\",systemImage:AppIcon.Settings.profile.rawValue)"))
        XCTAssertTrue(settingsTabs.contains("Label(\"User\",systemImage:AppIcon.Settings.user.rawValue)"))
        XCTAssertTrue(
            settingsTabs.contains(
                "Label(viewModel.assistantDisplayName,systemImage:AppIcon.Settings.assistant.rawValue)"
            )
        )
        XCTAssertTrue(settingsTabs.contains("Label(\"Skills\",systemImage:AppIcon.Settings.skills.rawValue)"))
        XCTAssertTrue(settingsTabs.contains("Label(\"More\",systemImage:AppIcon.Settings.more.rawValue)"))
        XCTAssertFalse(settingsTabs.contains("systemImage:\"person.crop.circle\""))
        XCTAssertFalse(settingsTabs.contains("systemImage:\"ellipsis.circle\""))

        XCTAssertTrue(settingsMore.contains("varappIcon:AppIcon{"))
        XCTAssertTrue(settingsMore.contains("Label(destination.title,systemImage:destination.appIcon.rawValue)"))
        XCTAssertFalse(settingsMore.contains("systemImage:destination.systemImage"))
    }

    private func assertSettingsProfileFormChromeUsesAppIcon() throws {
        let settingsMac = try normalizedSource(at: ["sideBar", "Views", "Settings", "SettingsMacStyles.swift"])
        let profileSupport = try normalizedSource(
            at: ["sideBar", "Views", "Settings", "SettingsSections+ProfileSupport.swift"]
        )
        let profileDOB = try normalizedSource(at: ["sideBar", "Views", "Settings", "ProfileDateOfBirthField.swift"])
        let settingsSystem = try normalizedSource(at: ["sideBar", "Views", "Settings", "SettingsSections+System.swift"])
        let settingsSystemMac = try normalizedSource(
            at: ["sideBar", "Views", "Settings", "SettingsSections+SystemMac.swift"]
        )

        XCTAssertTrue(settingsMac.contains("Image(appIcon:AppIcon.Navigation.chevronRight)"))
        XCTAssertTrue(settingsMac.contains("tone==.error?AppIcon.State.warningFilled:AppIcon.State.infoFilled"))
        XCTAssertFalse(settingsMac.contains("Image(systemName:\"chevron.right\")"))
        XCTAssertFalse(settingsMac.contains("\"exclamationmark.triangle.fill\":\"info.circle.fill\""))

        XCTAssertTrue(profileSupport.contains("Image(appIcon:AppIcon.Settings.profileFilled)"))
        XCTAssertFalse(profileSupport.contains("Image(systemName:\"person.crop.circle.fill\")"))

        XCTAssertTrue(profileDOB.contains("Image(appIcon:AppIcon.Action.clearFilled)"))
        XCTAssertFalse(profileDOB.contains("Image(systemName:\"xmark.circle.fill\")"))

        XCTAssertTrue(settingsSystem.contains("Image(appIcon:AppIcon.Action.clearFilled)"))
        XCTAssertFalse(settingsSystem.contains("Image(systemName:\"xmark.circle.fill\")"))
        XCTAssertTrue(settingsSystemMac.contains("Image(appIcon:AppIcon.Action.clearFilled)"))
        XCTAssertFalse(settingsSystemMac.contains("Image(systemName:\"xmark.circle.fill\")"))
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

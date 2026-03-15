import XCTest
@testable import sideBar

@MainActor
final class SettingsSectionsTests: XCTestCase {
    func testTextSizeControlModeUsesPickerOnIOS() {
        let mode = GeneralSettingsView.textSizeControlMode(for: .iOS)

        XCTAssertEqual(mode, .picker)
    }

    func testTextSizeControlModeUsesMenuPickerOnMacOS() {
        let mode = GeneralSettingsView.textSizeControlMode(for: .macOS)

        XCTAssertEqual(mode, .menuPicker)
    }

    func testShouldFlushAutosaveOnDisappearWhenDraftIsDirty() {
        let shouldFlush = ProfileSettingsView.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true,
            isSavingProfile: false
        )

        XCTAssertTrue(shouldFlush)
    }

    func testShouldNotFlushAutosaveOnDisappearWhenAlreadySaving() {
        let shouldFlush = ProfileSettingsView.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true,
            isSavingProfile: true
        )

        XCTAssertFalse(shouldFlush)
    }

    func testProfileShouldSyncDraftsWhenUserChangesEvenIfDraftDirty() {
        let shouldSync = ProfileSettingsView.shouldSyncDrafts(
            hasLoadedDrafts: true,
            isDraftDirty: true,
            previousUserId: "user-1",
            nextUserId: "user-2"
        )

        XCTAssertTrue(shouldSync)
    }

    func testUserShouldSyncDraftsWhenUserChangesEvenIfDraftDirty() {
        let shouldSync = UserSettingsView.shouldSyncDrafts(
            hasLoadedDrafts: true,
            isDraftDirty: true,
            previousUserId: "user-1",
            nextUserId: "user-2"
        )

        XCTAssertTrue(shouldSync)
    }

    func testSystemShouldFlushAutosaveOnDisappearWhenDirty() {
        let shouldFlush = UserSettingsView.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true,
            isSavingSystem: false
        )

        XCTAssertTrue(shouldFlush)
    }

    func testSystemShouldNotFlushAutosaveWhileSaving() {
        let shouldFlush = UserSettingsView.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true,
            isSavingSystem: true
        )

        XCTAssertFalse(shouldFlush)
    }

    func testDraftSynchronizerRespectsDirtyDraftsForSameUser() {
        let shouldSync = SettingsDraftSynchronizer.shouldSyncDrafts(
            hasLoadedDrafts: true,
            isDraftDirty: true,
            previousUserId: "user-1",
            nextUserId: "user-1"
        )

        XCTAssertFalse(shouldSync)
    }

    func testProfileDraftStateNormalizesPickerValuesAndDate() {
        let settings = UserSettings(
            userId: "user-1",
            communicationStyle: "",
            workingRelationship: "",
            name: "  Sean  ",
            jobTitle: "Founder",
            employer: "sideBar",
            dateOfBirth: "1990-01-01",
            gender: "MALE",
            pronouns: "He/Him",
            location: "London",
            profileImageUrl: nil,
            enabledSkills: [],
            installedStoreSkills: []
        )

        let draft = ProfileSettingsView.ProfileDraftState.from(settings: settings)

        XCTAssertFalse(draft.isDirty(comparedTo: settings))
        XCTAssertEqual(draft.gender, "male")
        XCTAssertEqual(draft.pronouns, "he/him")
        XCTAssertEqual(draft.dateOfBirth, "1990-01-01")
    }

    func testProfileDraftHydrationMatchesStoredSettings() {
        let settings = UserSettings(
            userId: "user-1",
            communicationStyle: "",
            workingRelationship: "",
            name: "Sean",
            jobTitle: "Founder",
            employer: "sideBar",
            dateOfBirth: "1990-01-01",
            gender: "male",
            pronouns: "he/him",
            location: "London",
            profileImageUrl: nil,
            enabledSkills: [],
            installedStoreSkills: []
        )

        let draft = ProfileSettingsView.ProfileDraftState.from(settings: settings)

        XCTAssertFalse(draft.isDirty(comparedTo: settings))
    }

    func testSettingsSaveStatusLogicShowsSavingThenSaved() {
        var timeline = SettingsSaveStatusLogic.timeline(
            wasSaving: false,
            isSaving: true,
            saveError: nil
        )

        XCTAssertEqual(timeline.immediateState, .saving)

        timeline = SettingsSaveStatusLogic.timeline(
            wasSaving: true,
            isSaving: false,
            saveError: nil
        )

        XCTAssertEqual(timeline.immediateState, .saved)
    }

    func testSettingsSaveStatusLogicShowsErrorWhenErrorPresent() {
        let timeline = SettingsSaveStatusLogic.timeline(
            wasSaving: true,
            isSaving: false,
            saveError: "boom"
        )

        XCTAssertEqual(timeline.immediateState, .error)
    }

    func testSettingsSaveStatusLogicReturnsNilWhenIdle() {
        let timeline = SettingsSaveStatusLogic.timeline(
            wasSaving: false,
            isSaving: false,
            saveError: nil
        )

        XCTAssertNil(timeline.immediateState)
    }

    func testSettingsSaveStatusLogicErrorTakesPrecedenceOverSaving() {
        let timeline = SettingsSaveStatusLogic.timeline(
            wasSaving: false,
            isSaving: true,
            saveError: "boom"
        )

        XCTAssertEqual(timeline.immediateState, .error)
    }

    func testPickerOptionsReturnsBaseOptionsWhenCurrentValueIsEmpty() {
        let baseOptions = ["he/him", "she/her"]

        let options = ProfileSettingsView.pickerOptions(base: baseOptions, currentValue: "")

        XCTAssertEqual(options, baseOptions)
    }

    func testPickerOptionsPrependsCurrentValueWhenCurrentValueIsCustom() {
        let baseOptions = ["he/him", "she/her"]

        let options = ProfileSettingsView.pickerOptions(
            base: baseOptions,
            currentValue: "xe/xem"
        )

        XCTAssertEqual(options, ["xe/xem", "he/him", "she/her"])
    }

    func testPickerOptionsDoesNotDuplicateCaseInsensitiveExistingValue() {
        let baseOptions = ["he/him", "she/her"]

        let options = ProfileSettingsView.pickerOptions(
            base: baseOptions,
            currentValue: "He/Him"
        )

        XCTAssertEqual(options, baseOptions)
    }

    func testNormalizedPickerSelectionUsesCanonicalOptionCasing() {
        let normalized = ProfileSettingsView.normalizedPickerSelection(
            currentValue: "He/Him",
            base: ["he/him", "she/her"]
        )

        XCTAssertEqual(normalized, "he/him")
    }

    func testPickerValuesEquivalentIgnoresCaseAndWhitespace() {
        let equivalent = ProfileSettingsView.pickerValuesEquivalent("he/him", " He/Him ")

        XCTAssertTrue(equivalent)
    }

    func testAssistantSectionTitleUsesAssistantDisplayName() {
        let title = AgentSettingsView.assistantSectionTitle("Tone", assistantDisplayName: "Navigator")

        XCTAssertEqual(title, "Navigator's Tone")
    }

    func testMacSettingsSidebarUsesStableWidth() {
        XCTAssertEqual(settingsMacSidebarWidth(), 232)
    }

    func testMacSettingsRowLabelWidthSupportsInspectorLayout() {
        XCTAssertEqual(settingsMacRowLabelWidth(), 160)
    }

    func testMacSettingsSectionIntroSpacingUsesInspectorRhythm() {
        XCTAssertEqual(settingsMacSectionIntroSpacing(), 6)
    }

    func testProfileSettingsMacSourceUsesInspectorRowsAndStatusBanners() throws {
        let normalized = try profileSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsMacSectionIntro("))
        XCTAssertTrue(normalized.contains("SettingsMacHeroButtonRow("))
        XCTAssertTrue(normalized.contains("SettingsMacFieldRow("))
        XCTAssertTrue(normalized.contains("SettingsMacStatusBanner("))
        XCTAssertTrue(normalized.contains("SettingsMacActionSection("))
    }

    func testGeneralSettingsMacSourceUsesInspectorSectionIntrosAndCalmerWeatherControl() throws {
        let normalized = try generalSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsMacSectionIntro("))
        XCTAssertTrue(normalized.contains("SettingsMacActionSection("))
        XCTAssertTrue(normalized.contains("settingsMacWeatherPickerStyle()"))
        XCTAssertFalse(normalized.contains(".pickerStyle(.radioGroup)"))
    }

    func testSkillsSettingsMacSourceUsesInspectorIntroAndCardRows() throws {
        let normalized = try skillsSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsMacSectionIntro("))
        XCTAssertTrue(normalized.contains("SettingsMacStatusBanner("))
        XCTAssertTrue(normalized.contains("SettingsMacSkillRow("))
    }

    func testMemoriesSettingsMacRoutingUsesInspectorDetailInsteadOfPlaceholderForm() throws {
        let normalized = try memoriesSettingsRoutingSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("MemoriesSettingsDetailView(viewModel:viewModel)"))
        XCTAssertFalse(normalized.contains("Form{Section(\"Memories\")"))
    }

    func testMemoriesSettingsMacSourceUsesInspectorShellInsteadOfPlaceholderForm() throws {
        let normalized = try memoriesSettingsDetailSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsMacSectionIntro("))
        XCTAssertTrue(normalized.contains("SettingsMacStatusBanner("))
        XCTAssertTrue(normalized.contains("SettingsMacSkillRow("))
    }

    func testStoreSkillConfigUsesInspectorCardsAndStatusBanners() throws {
        let normalized = try storeSkillConfigSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsMacSectionIntro("))
        XCTAssertTrue(normalized.contains("SettingsMacStatusBanner("))
        XCTAssertTrue(normalized.contains("SettingsMacActionSection("))
    }

    func testUserSettingsMacSourceUsesInspectorCardsAndStatusBanners() throws {
        let normalized = try systemMacSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsMacPanelCard"))
        XCTAssertTrue(normalized.contains("SettingsMacSectionIntro("))
        XCTAssertTrue(normalized.contains("SettingsMacStatusBanner("))
    }

    func testAgentSettingsMacSourceUsesInspectorCardsAndStatusBanners() throws {
        let normalized = try systemMacSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsMacPanelCard"))
        XCTAssertTrue(normalized.contains("SettingsMacSectionIntro("))
        XCTAssertTrue(normalized.contains("SettingsMacStatusBanner("))
        XCTAssertTrue(normalized.contains("SettingsMacFieldRow("))
    }

    func testUtilitiesSettingsMacSourceUsesInspectorCardsAndStatusBanners() throws {
        let normalized = try utilitiesSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsMacPanelCard"))
        XCTAssertTrue(normalized.contains("SettingsMacSectionIntro("))
        XCTAssertTrue(normalized.contains("SettingsMacStatusBanner("))
    }

    func testStoreSkillCredentialsUsesInspectorRowsAndStatusBanners() throws {
        let normalized = try storeSkillCredentialsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsMacSkillRow("))
        XCTAssertTrue(normalized.contains("SettingsMacStatusBanner("))
    }
}

private func settingsSourceRoot(
    file: StaticString = #filePath
) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Settings")
}

private func profileSettingsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("SettingsSections.swift", file: file, line: line)
}

private func generalSettingsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("SettingsSections+General.swift", file: file, line: line)
}

private func skillsSettingsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("SettingsSections+Additional.swift", file: file, line: line)
}

private func memoriesSettingsRoutingSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("SettingsSections+Utilities.swift", file: file, line: line)
}

private func memoriesSettingsDetailSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("MemoriesSettingsView.swift", file: file, line: line)
}

private func storeSkillConfigSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("StoreSkillConfigView.swift", file: file, line: line)
}

private func systemSettingsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("SettingsSections+System.swift", file: file, line: line)
}

private func systemMacSettingsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("SettingsSections+SystemMac.swift", file: file, line: line)
}

private func utilitiesSettingsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("SettingsSections+Utilities.swift", file: file, line: line)
}

private func storeSkillCredentialsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try settingsSourceFile("StoreSkillCredentialsView.swift", file: file, line: line)
}

private func settingsSourceFile(
    _ filename: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let sourceURL = settingsSourceRoot(file: file).appendingPathComponent(filename)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(filename): \(error)", file: file, line: line)
        throw error
    }
}

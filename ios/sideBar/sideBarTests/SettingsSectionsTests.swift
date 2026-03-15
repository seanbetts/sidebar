import XCTest
@testable import sideBar

// swiftlint:disable file_length

@MainActor
// swiftlint:disable:next type_body_length
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

    func testProfileShouldNotSyncDraftsWhenUserUnchangedAndDirty() {
        let shouldSync = ProfileSettingsView.shouldSyncDrafts(
            hasLoadedDrafts: true,
            isDraftDirty: true,
            previousUserId: "user-1",
            nextUserId: "user-1"
        )

        XCTAssertFalse(shouldSync)
    }

    func testUserShouldNotSyncDraftsWhenUserUnchangedAndDirty() {
        let shouldSync = UserSettingsView.shouldSyncDrafts(
            hasLoadedDrafts: true,
            isDraftDirty: true,
            previousUserId: "user-1",
            nextUserId: "user-1"
        )

        XCTAssertFalse(shouldSync)
    }

    func testSystemShouldFlushAutosaveOnDisappearWhenDirty() {
        let shouldFlush = UserSettingsView.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true,
            isSavingSystem: false,
            isAutosaveSaving: false
        )

        XCTAssertTrue(shouldFlush)
    }

    func testSystemShouldNotFlushAutosaveWhileSaving() {
        let shouldFlush = UserSettingsView.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true,
            isSavingSystem: true,
            isAutosaveSaving: false
        )

        XCTAssertFalse(shouldFlush)
    }

    func testSystemShouldNotFlushWhileAutosaveSaving() {
        let shouldFlush = UserSettingsView.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true,
            isSavingSystem: false,
            isAutosaveSaving: true
        )

        XCTAssertFalse(shouldFlush)
    }

    func testSystemShouldNotFlushAutosaveBeforeDraftsLoad() {
        let shouldFlush = UserSettingsView.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: false,
            isSyncingDrafts: false,
            isDraftDirty: true,
            isSavingSystem: false,
            isAutosaveSaving: false
        )

        XCTAssertFalse(shouldFlush)
    }

    func testSystemAutosaveFlushUsesManualSaveWhenScheduled() async {
        let controller = SystemAutosaveController(delayNs: 100_000_000)
        var autosaveRan = false
        var flushRan = false

        controller.scheduleAutosave(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true
        ) {
            autosaveRan = true
        }

        controller.flushPendingAutosave(
            shouldFlush: true
        ) {
            flushRan = true
        }

        let didRunFlushSave = await waitUntil(timeoutNs: 1_000_000_000) {
            flushRan
        }

        XCTAssertTrue(didRunFlushSave)
        XCTAssertTrue(flushRan)
        XCTAssertFalse(autosaveRan)
    }

    func testSystemAutosaveFlushSkipsWhenAutosaveInFlight() async {
        let controller = SystemAutosaveController(delayNs: 0)
        var autosaveRuns = 0
        var flushRuns = 0

        controller.scheduleAutosave(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true
        ) {
            autosaveRuns += 1
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let didBeginAutosave = await waitUntil(timeoutNs: 1_000_000_000) {
            controller.isAutosaveSaving
        }
        XCTAssertTrue(didBeginAutosave)
        controller.flushPendingAutosave(
            shouldFlush: true
        ) {
            flushRuns += 1
        }

        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(autosaveRuns, 1)
        XCTAssertEqual(flushRuns, 0)
    }

    func testSystemAutosaveFlushSkipsManualSaveWhenAutosaveAlreadyCompleted() async {
        let controller = SystemAutosaveController(delayNs: 0)
        var autosaveRuns = 0
        var flushRuns = 0

        controller.scheduleAutosave(
            hasLoadedDrafts: true,
            isSyncingDrafts: false,
            isDraftDirty: true
        ) {
            autosaveRuns += 1
        }

        let didCompleteAutosave = await waitUntil(timeoutNs: 1_000_000_000) {
            autosaveRuns == 1 && !controller.isAutosaveSaving
        }
        XCTAssertTrue(didCompleteAutosave)
        controller.flushPendingAutosave(
            shouldFlush: true
        ) {
            flushRuns += 1
        }

        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(autosaveRuns, 1)
        XCTAssertEqual(flushRuns, 0)
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

    func testDraftSynchronizerSyncsWhenDraftsUnloadedEvenIfDirty() {
        let shouldSync = SettingsDraftSynchronizer.shouldSyncDrafts(
            hasLoadedDrafts: false,
            isDraftDirty: true,
            previousUserId: "user-1",
            nextUserId: "user-1"
        )

        XCTAssertTrue(shouldSync)
    }

    func testUserShouldSyncDraftsWhenDraftCleanAndUserUnchanged() {
        let shouldSync = UserSettingsView.shouldSyncDrafts(
            hasLoadedDrafts: true,
            isDraftDirty: false,
            previousUserId: "user-1",
            nextUserId: "user-1"
        )

        XCTAssertTrue(shouldSync)
    }

    func testSettingsDraftSynchronizerIgnoresWhitespaceWhenUserIdMatches() {
        let shouldSync = SettingsDraftSynchronizer.shouldSyncDrafts(
            hasLoadedDrafts: true,
            isDraftDirty: true,
            previousUserId: " user-1 ",
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

    func testProfileDraftHydrationHandlesCaseInsensitivePickerValuesWithWhitespace() {
        let settings = UserSettings(
            userId: "user-1",
            communicationStyle: "",
            workingRelationship: "",
            name: "Sean",
            jobTitle: "Founder",
            employer: "sideBar",
            dateOfBirth: "1990-01-01",
            gender: " MALE ",
            pronouns: " He/Him ",
            location: "London",
            profileImageUrl: nil,
            enabledSkills: [],
            installedStoreSkills: []
        )

        let draft = ProfileSettingsView.ProfileDraftState.from(settings: settings)

        XCTAssertFalse(draft.isDirty(comparedTo: settings))
        XCTAssertEqual(draft.gender, "male")
        XCTAssertEqual(draft.pronouns, "he/him")
    }

    func testProfileDraftHydrationTrimsStoredTextFieldsBeforeDisplay() {
        let settings = UserSettings(
            userId: "user-1",
            communicationStyle: "",
            workingRelationship: "",
            name: " Sean ",
            jobTitle: " Founder ",
            employer: " sideBar ",
            dateOfBirth: "1990-01-01",
            gender: "male",
            pronouns: "he/him",
            location: " London ",
            profileImageUrl: nil,
            enabledSkills: [],
            installedStoreSkills: []
        )

        let draft = ProfileSettingsView.ProfileDraftState.from(settings: settings)

        XCTAssertEqual(draft.name, "Sean")
        XCTAssertEqual(draft.jobTitle, "Founder")
        XCTAssertEqual(draft.employer, "sideBar")
        XCTAssertEqual(draft.location, "London")
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

    func testSettingsSaveStatusLogicTreatsWhitespaceErrorAsNil() {
        let timeline = SettingsSaveStatusLogic.timeline(
            wasSaving: true,
            isSaving: false,
            saveError: "   "
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

    func testSettingsSaveStatusLogicContinuesSavingWhenStillInFlight() {
        let timeline = SettingsSaveStatusLogic.timeline(
            wasSaving: true,
            isSaving: true,
            saveError: nil
        )

        XCTAssertEqual(timeline.immediateState, .saving)
    }

    func testSettingsSaveStatusLogicReturnsNilWhenIdleSecondAssertion() {
        let timeline = SettingsSaveStatusLogic.timeline(
            wasSaving: false,
            isSaving: false,
            saveError: nil
        )

        XCTAssertNil(timeline.immediateState)
    }

    func testSettingsSaveStatusLogicSequenceTransitionsFromSavingToSavedToNil() {
        var wasSaving = false
        var recordedStates: [SettingsSavePillState?] = []

        let first = SettingsSaveStatusLogic.timeline(
            wasSaving: wasSaving,
            isSaving: true,
            saveError: nil
        )
        recordedStates.append(first.immediateState)
        wasSaving = true

        let second = SettingsSaveStatusLogic.timeline(
            wasSaving: wasSaving,
            isSaving: false,
            saveError: nil
        )
        recordedStates.append(second.immediateState)
        wasSaving = false

        let third = SettingsSaveStatusLogic.timeline(
            wasSaving: wasSaving,
            isSaving: false,
            saveError: nil
        )
        recordedStates.append(third.immediateState)

        XCTAssertEqual(recordedStates, [.saving, .saved, nil])
    }

    private func waitUntil(
        timeoutNs: UInt64,
        pollNs: UInt64 = 5_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNs
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNs)
        }
        return false
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

    func testProfileSettingsMacSourceUsesPromptBasedTextFields() throws {
        let normalized = try profileSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("TextField(text:$name,prompt:Text(\"Notset\"))"))
        XCTAssertTrue(normalized.contains("TextField(text:$jobTitle,prompt:Text(\"Notset\"))"))
        XCTAssertTrue(normalized.contains("TextField(text:$employer,prompt:Text(\"Notset\"))"))
        XCTAssertTrue(normalized.contains("TextField(text:$location,prompt:Text(\"Notset\"))"))
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

    func testSkillsSettingsMacSourceSeparatesTierNavigationFromBulkActions() throws {
        let normalized = try skillsSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Picker(\"SkillType\",selection:$selectedTier)"))
        XCTAssertTrue(normalized.contains(".frame(maxWidth:.infinity)"))
        XCTAssertTrue(normalized.contains("Text(\"Enableall\")"))
        XCTAssertFalse(normalized.contains("SettingsMacFieldRow(\"Bulkactions\")"))
        XCTAssertFalse(normalized.contains("SettingsMacSectionIntro(title:\"SkillType\""))
    }

    func testUserSettingsMacSourceUsesTransparentEditors() throws {
        let normalized = try systemMacSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".fill(.clear)"))
        XCTAssertTrue(normalized.contains(".scrollContentBackground(.hidden)"))
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

    func testMemoriesSettingsMacSourceUsesSingleColumnInspectorFlow() throws {
        let normalized = try memoriesSettingsDetailSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("HStack(alignment:.top"))
        XCTAssertTrue(normalized.contains("ScrollView{VStack(alignment:.leading"))
        XCTAssertTrue(normalized.contains("detailInspectorContent"))
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

    func testSystemMacSourceFlushesAutosaveOnDisappear() throws {
        let normalized = try systemMacSettingsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".onDisappear{flushPendingSystemAutosave()"))
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

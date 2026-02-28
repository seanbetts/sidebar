import XCTest
@testable import sideBar

@MainActor
final class SettingsSectionsTests: XCTestCase {
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
}

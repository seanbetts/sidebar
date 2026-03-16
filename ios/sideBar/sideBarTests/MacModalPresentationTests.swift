import XCTest
@testable import sideBar

@MainActor
final class MacModalPresentationTests: XCTestCase {
    func testChooserPanelsUseMediumWidthPreset() {
        XCTAssertEqual(
            macModalWidthPreset(for: .chooserSheet),
            .medium
        )
    }

    func testSettingsMapsToLargeInspectorPanel() {
        XCTAssertEqual(
            settingsMacPresentationPanelType(),
            .largeInspectorSheet
        )
    }

    func testInspectorPresetUsesLargestWidth() {
        XCTAssertEqual(
            macModalFrameWidth(for: .largeInspectorSheet),
            960
        )
    }

    func testTaskNotesUsesEditorPanelType() {
        XCTAssertEqual(taskNotesMacPanelType(), .editorSheet)
    }

    func testRenameItemUsesCompactSheetPanelType() {
        XCTAssertEqual(renameItemMacPanelType(), .compactSheet)
    }

    func testIngestionCenterUsesCompactPopoverPanelType() {
        XCTAssertEqual(ingestionCenterPanelType(), .compactPopover)
    }

    func testScratchpadUsesEditorPanelType() {
        XCTAssertEqual(scratchpadPopoverPanelType(), .editorSheet)
    }

    func testQueuedChangesUsesChooserPanelType() {
        XCTAssertEqual(queuedChangesPanelType(), .chooserSheet)
    }

    func testStoreInstallPromptUsesCompactSheetPanelType() {
        XCTAssertEqual(storeInstallPromptPanelType(), .compactSheet)
    }
}

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

    func testDeprecatedIngestionCenterPresentationIsRemoved() throws {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ingestionCenterSourcePath()),
            "IngestionCenterView should stay removed now that ingestion progress is surfaced through header status and Live Activities."
        )

        let source = try macModalPresentationSource().normalizedForSourceAssertions()
        XCTAssertFalse(source.contains("funcingestionCenterPanelType()"))
    }

    func testScratchpadUsesEditorPanelType() {
        XCTAssertEqual(scratchpadPopoverPanelType(), .editorSheet)
        XCTAssertEqual(macModalFrameWidth(for: scratchpadPopoverPanelType()), 640)
    }

    func testQueuedChangesUsesChooserPanelType() {
        XCTAssertEqual(queuedChangesPanelType(), .chooserSheet)
    }

    func testStoreInstallPromptUsesCompactSheetPanelType() {
        XCTAssertEqual(storeInstallPromptPanelType(), .compactSheet)
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func ingestionCenterSourcePath(
    file: StaticString = #filePath
) -> String {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Files")
        .appendingPathComponent("IngestionCenterView.swift")
        .path
}

private func macModalPresentationSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let sourceURL = URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Design")
        .appendingPathComponent("Components")
        .appendingPathComponent("MacModalPresentation.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read MacModalPresentation.swift: \(error)", file: file, line: line)
        return ""
    }
}

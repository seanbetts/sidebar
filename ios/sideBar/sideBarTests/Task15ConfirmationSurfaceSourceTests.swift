import XCTest

final class Task15ConfirmationSurfaceSourceTests: XCTestCase {
    func testSharedConfirmationHelpersCoverDestructiveAndActionDialogs() throws {
        let normalized = try sourceFile("Design/Components/DeleteConfirmationAlert.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("funcdestructiveConfirmationAlert("))
        XCTAssertTrue(normalized.contains("funcdeleteConfirmationAlert("))
        XCTAssertTrue(normalized.contains("funcactionConfirmationDialog<Actions:View>("))
        XCTAssertTrue(normalized.contains("titleVisibility:.visible"))
        XCTAssertTrue(normalized.contains("Button(cancelTitle,role:.cancel)"))
    }

    func testProfilePhotoSourceDialogsUseSharedActionConfirmationDialog() throws {
        let normalized = try sourceFile("Views/Settings/SettingsSections.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertEqual(
            normalized.components(separatedBy: ".actionConfirmationDialog(").count - 1,
            2
        )
        XCTAssertFalse(normalized.contains(".confirmationDialog("))
        XCTAssertFalse(normalized.contains("Button(\"Cancel\",role:.cancel){}"))
    }

    func testTasksProjectGroupChooserUsesSharedActionConfirmationDialog() throws {
        let normalized = try sourceFile("Views/SidebarPanels/TasksPanel.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".actionConfirmationDialog("))
        XCTAssertFalse(normalized.contains(".confirmationDialog(\"Choosegroup\""))
        XCTAssertFalse(normalized.contains("Button(\"Cancel\",role:.cancel){showProjectGroupDialog=false}"))
    }

    func testStoreSkillDetailSheetUsesSharedDestructiveConfirmationAlert() throws {
        let normalized = try sourceFile("Views/SkillsStore/StoreSkillDetailSheet.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".destructiveConfirmationAlert("))
        XCTAssertTrue(normalized.contains("confirmTitle:\"Uninstall\""))
        XCTAssertFalse(normalized.contains(".alert(\"Uninstallskill?\""))
    }
}

private func sourceFile(
    _ relativePath: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent(relativePath)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(relativePath): \(error)", file: file, line: line)
        throw error
    }
}

import XCTest

final class SkillsStoreViewSourceTests: XCTestCase {
    func testSkillsStoreSourceUsesSharedDestructiveConfirmationAlertForUninstall() throws {
        let normalized = try skillsStoreViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".destructiveConfirmationAlert("))
        XCTAssertTrue(normalized.contains("confirmTitle:\"Uninstall\""))
        XCTAssertFalse(normalized.contains(".alert(\"Uninstallskill?\""))
    }

    func testSkillsStoreCardsAndFiltersUseSharedHoverHighlight() throws {
        let normalized = try skillsStoreCardComponentsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("@StateprivatevarisHovered=false"))
        XCTAssertTrue(normalized.contains(".sidebarHover($isHovered)"))
        XCTAssertTrue(normalized.contains("DesignTokens.Colors.sidebarHoverBackground"))
    }
}

private func skillsStoreViewSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SkillsStore")
        .appendingPathComponent("SkillsStoreDetailView.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SkillsStoreDetailView.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func skillsStoreCardComponentsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SkillsStore")
        .appendingPathComponent("SkillsStoreCardComponents.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SkillsStoreCardComponents.swift: \(error)", file: file, line: line)
        throw error
    }
}

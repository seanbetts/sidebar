import XCTest

final class CompactPhonePanelSpacingSourceTests: XCTestCase {
    func testSidebarPanelListStyleReducesCompactPhoneSectionHeaderGap() throws {
        let normalized = try panelComponentsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "funcsidebarPanelListStyle(reducesCompactPhoneSectionHeaderGap:Bool=false)->someView{"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                ".environment(\\.defaultMinListHeaderHeight,LayoutMetrics.compactPhonePanelSectionHeaderMinHeight)"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "funcsidebarCompactPhoneTopPadding(_padding:CGFloat,isCompactPhone:Bool)->someView{"
            )
        )
    }

    func testSkillsStoreCompactPhoneUsesTighterTopPadding() throws {
        let normalized = try skillsStoreSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                ".padding(.top,isCompactPhone?LayoutMetrics.compactPhonePanelTopContentPadding:DesignTokens.Spacing.lg)"
            )
        )
    }

    func testConversationsPanelAppliesCompactPhoneTopPaddingAdjustment() throws {
        let normalized = try sidebarPanelSource(named: "ConversationsPanelView+Helpers.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                ".sidebarCompactPhoneTopPadding(LayoutMetrics.compactPhoneSectionedPanelTopPaddingAdjustment,isCompactPhone:isCompactPhone)"
            )
        )
    }

    func testTasksPanelAppliesCompactPhoneTopPadding() throws {
        let normalized = try sidebarPanelSource(named: "TasksPanel.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                ".sidebarCompactPhoneTopPadding(LayoutMetrics.compactPhoneTasksPanelTopPadding,isCompactPhone:isCompactPhone)"
            )
        )
    }

    private func panelComponentsSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        try sidebarPanelSource(
            named: "PanelComponents.swift",
            file: file,
            line: line
        )
    }

    private func sidebarPanelSource(
        named fileName: String,
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
            .appendingPathComponent("SidebarPanels")
            .appendingPathComponent(fileName)

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read sidebar panel source: \(error)", file: file, line: line)
            throw error
        }
    }

    private func skillsStoreSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
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
            XCTFail("Failed to read skills store source: \(error)", file: file, line: line)
            throw error
        }
    }
}

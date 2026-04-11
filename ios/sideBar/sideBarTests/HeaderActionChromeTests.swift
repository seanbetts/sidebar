import XCTest
@testable import sideBar

final class HeaderActionChromeTests: XCTestCase {
    func testSharedHeaderActionControlMetricsMatchStandaloneGlassChrome() {
        XCTAssertEqual(HeaderActionControlMetrics.symbolPointSize, DesignTokens.Icon.sm)
        XCTAssertEqual(HeaderActionControlMetrics.iconFrameWidth, 28)
        XCTAssertEqual(HeaderActionControlMetrics.iconFrameHeight, 20)
        XCTAssertEqual(HeaderActionControlMetrics.rowSpacing, DesignTokens.Spacing.xs)
        XCTAssertEqual(
            HeaderActionControlMetrics.chromeWidth,
            HeaderActionControlMetrics.iconFrameWidth + (HeaderActionControlMetrics.chromePadding * 2)
        )
        XCTAssertEqual(
            HeaderActionControlMetrics.chromeHeight,
            HeaderActionControlMetrics.iconFrameHeight + (HeaderActionControlMetrics.chromePadding * 2)
        )
    }

    func testGlassHeaderActionButtonsUseSharedActionButtonChrome() {
        XCTAssertEqual(HeaderActionControlChromeStyle.glass.kind, .actionButton)
    }

    func testSharedHeaderActionRowIsSpacingOnlyContainer() throws {
        let normalized = try headerActionComponentSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("structHeaderActionRow<Content:View>:View{"))
        XCTAssertTrue(normalized.contains("HStack(spacing:spacing){content}"))
        XCTAssertFalse(normalized.contains("HeaderActionGroupChromeStyle"))
        XCTAssertFalse(normalized.contains("headerActionGroupChrome("))
    }

    func testSidebarPanelUtilityActionsUseStandaloneGlassChrome() {
        XCTAssertEqual(ConversationsPanelView.actionControlChromeStyle, .glass)
        XCTAssertEqual(NotesPanelView.actionControlChromeStyle, .glass)
        XCTAssertEqual(FilesPanelView.actionControlChromeStyle, .glass)
        XCTAssertEqual(TasksPanelView.actionControlChromeStyle, .glass)
        XCTAssertEqual(WebsitesPanelView.actionControlChromeStyle, .glass)
    }

    func testNotesAndWebsitesDetailHeaderActionsUseStandaloneGlassChrome() {
        XCTAssertEqual(NotesDetailView.actionControlChromeStyle, .glass)
        XCTAssertEqual(WebsitesDetailView.actionControlChromeStyle, .glass)
    }

    func testSharedHeaderActionRowUsesSharedSpacingMetricByDefault() throws {
        let normalized = try headerActionComponentSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("spacing:CGFloat=HeaderActionControlMetrics.rowSpacing"))
    }

    func testChatAndFilesHeadersDoNotCarryRowChromeOverrides() throws {
        let chatNormalized = try chatHeaderSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let filesNormalized = try headerActionSource(named: "FilesHeaderActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(chatNormalized.contains("actionRowChromeStyle"))
        XCTAssertFalse(chatNormalized.contains("chromeStyle:Self.actionRowChromeStyle"))
        XCTAssertFalse(filesNormalized.contains("actionRowChromeStyle"))
        XCTAssertFalse(filesNormalized.contains("chromeStyle:Self.actionRowChromeStyle"))
    }

    func testMacOSFilesMenuAppliesChromeToMenuControl() throws {
        let normalized = try headerActionSource(named: "FilesHeaderActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains("HeaderActionMenuControl(")
        )
    }

    func testMacOSNotesMenuAppliesChromeToMenuControl() throws {
        let normalized = try headerActionSource(named: "NotesDetailView+MenuActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains("HeaderActionMenuControl(")
        )
    }

    func testMacOSWebsitesMenuAppliesChromeToMenuControl() throws {
        let normalized = try headerActionSource(named: "WebsitesDetailView+MenuActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains("HeaderActionMenuControl(")
        )
    }

    func testMacOSTasksAddMenuUsesSharedHeaderActionMenuControl() throws {
        let normalized = try headerActionSource(named: "TasksPanel+AddMenu.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains("HeaderActionMenuControl(")
        )
    }

    func testSharedHeaderActionMenuControlHidesMenuIndicator() throws {
        let normalized = try headerActionComponentSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(".menuIndicator(.hidden)")
        )
    }

    func testSharedIOSMenuButtonUsesSharedHeaderActionMenuControl() throws {
        let normalized = try headerActionComponentSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(".frame(width:HeaderActionControlMetrics.iconFrameWidth,height:HeaderActionControlMetrics.iconFrameHeight)")
        )
        XCTAssertTrue(
            normalized.contains("HeaderActionMenuControl(")
        )
        XCTAssertFalse(normalized.contains("UIKitMenuButton("))
    }

    func testNotesDetailiOSUsesSharedHeaderActionMenuButtonPath() throws {
        let normalized = try headerActionSource(named: "NotesDetailView+MenuActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("NoteActionsMenuButton("))
    }

    func testCompactPhoneToolbarMenusUsePlainChrome() throws {
        let notesNormalized = try headerActionSource(named: "NotesDetailView+MenuActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let websitesNormalized = try headerActionSource(named: "WebsitesDetailView+MenuActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let filesNormalized = try headerActionSource(named: "FilesHeaderActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(notesNormalized.contains("varnoteToolbarMenu:someView{HeaderActionMenuButton("))
        XCTAssertTrue(notesNormalized.contains("chromeStyle:.plain"))
        XCTAssertTrue(websitesNormalized.contains("varwebsiteToolbarMenu:someView{HeaderActionMenuButton("))
        XCTAssertTrue(websitesNormalized.contains("chromeStyle:.plain"))
        XCTAssertTrue(filesNormalized.contains("compactPhoneToolbarChromeStyle"))
        XCTAssertTrue(filesNormalized.contains("returnisCompact&&isPhone?.plain:Self.actionControlChromeStyle"))
    }
}

private func headerActionSource(
    named fileName: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")

    let sourceURL: URL
    switch fileName {
    case "FilesHeaderActions.swift":
        sourceURL = sourceRoot
            .appendingPathComponent("Files")
            .appendingPathComponent(fileName)
    case "NotesDetailView+MenuActions.swift":
        sourceURL = sourceRoot
            .appendingPathComponent("Notes")
            .appendingPathComponent(fileName)
    case "WebsitesDetailView+MenuActions.swift":
        sourceURL = sourceRoot
            .appendingPathComponent("Websites")
            .appendingPathComponent(fileName)
    case "TasksPanel+AddMenu.swift":
        sourceURL = sourceRoot
            .appendingPathComponent("SidebarPanels")
            .appendingPathComponent(fileName)
    default:
        XCTFail("Unsupported header action source: \(fileName)", file: file, line: line)
        throw NSError(domain: "HeaderActionChromeTests", code: 1)
    }

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(fileName): \(error)", file: file, line: line)
        throw error
    }
}

private func headerActionComponentSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Design")
        .appendingPathComponent("Components")
        .appendingPathComponent("HeaderActionIcon.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read HeaderActionIcon.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func chatHeaderSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Chat")
        .appendingPathComponent("ChatHeaderView.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read ChatHeaderView.swift: \(error)", file: file, line: line)
        throw error
    }
}

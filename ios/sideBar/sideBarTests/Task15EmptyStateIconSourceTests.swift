import XCTest

final class Task15EmptyStateIconSourceTests: XCTestCase {
    func testSharedEmptySearchStatusComponentsUseAppIconVocabulary() throws {
        try assertNoForbiddenIconPatterns([
            (
                ["sideBar", "Design", "Components", "EmptyStateContent.swift"],
                [
                    "varsystemImage:String?{",
                    "init(title:String,subtitle:String?=nil,systemImage:String)",
                    "systemImage:String",
                    "systemImage:\"magnifyingglass\"",
                    "systemImage:\"checkmark.circle\""
                ]
            ),
            (
                ["sideBar", "Design", "Components", "EmptyStateView.swift"],
                [
                    "varsystemImage:String?{",
                    "init(title:String,subtitle:String?=nil,systemImage:String?)",
                    "Image(systemName:systemImage)"
                ]
            ),
            (
                ["sideBar", "Design", "Components", "SearchField.swift"],
                [
                    "Image(systemName:\"magnifyingglass\")",
                    "Image(systemName:\"xmark.circle.fill\")"
                ]
            ),
            (
                ["sideBar", "Design", "Components", "OfflineBanner.swift"],
                [
                    "Image(systemName:\"wifi.slash\")",
                    "Image(systemName:\"wifi.exclamationmark\")"
                ]
            ),
            (
                ["sideBar", "Design", "Components", "StatusPill.swift"],
                [
                    "variconName:String?",
                    "\"info.circle.fill\"",
                    "\"checkmark.circle.fill\"",
                    "\"exclamationmark.triangle.fill\"",
                    "Image(systemName:iconName)"
                ]
            ),
            (
                ["sideBar", "Design", "Components", "SuccessCheckBadge.swift"],
                ["Image(systemName:\"checkmark\")"]
            )
        ])
    }

    func testCorePanelEmptyStatesRenderAppIconDirectly() throws {
        let files = try normalizedSource(at: ["sideBar", "Views", "SidebarPanels", "FilesPanel.swift"])
        let websites = try normalizedSource(at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel.swift"])
        let conversations = try normalizedSource(at: ["sideBar", "Views", "SidebarPanels", "ConversationsPanel.swift"])
        let notes = try normalizedSource(at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+Helpers.swift"])

        let expectedFilesEmptyState = [
            "EmptyStateContent.noContentYet(title:\"Nofilesyet\",",
            "subtitle:\"Uploadorcreateafiletogetstarted.\",",
            "icon:AppIcon.Domain.files)"
        ].joined()
        XCTAssertTrue(files.contains(expectedFilesEmptyState))
        XCTAssertTrue(files.contains("EmptyStateView(title:emptyState.title,subtitle:emptyState.subtitle,icon:emptyState.icon)"))
        XCTAssertFalse(files.contains("systemImage:emptyState.systemImage"))

        let expectedWebsitesEmptyState = [
            "EmptyStateContent.noContentYet(title:\"Nowebsitesyet\",",
            "subtitle:\"Savealinktogetstarted.\",",
            "icon:AppIcon.Domain.websites)"
        ].joined()
        XCTAssertTrue(websites.contains(expectedWebsitesEmptyState))
        XCTAssertTrue(websites.contains("EmptyStateView(title:emptyState.title,subtitle:emptyState.subtitle,icon:emptyState.icon)"))
        XCTAssertFalse(websites.contains("systemImage:emptyState.systemImage"))

        XCTAssertTrue(
            conversations.contains("EmptyStateView(title:emptyState.title,subtitle:emptyState.subtitle,icon:emptyState.icon)")
        )
        XCTAssertFalse(conversations.contains("systemImage:emptyState.systemImage"))

        XCTAssertTrue(notes.contains("EmptyStateView(title:emptyState.title,subtitle:emptyState.subtitle,icon:emptyState.icon)"))
        XCTAssertFalse(notes.contains("systemImage:emptyState.systemImage"))
    }
}

private extension Task15EmptyStateIconSourceTests {
    func assertNoForbiddenIconPatterns(
        _ forbiddenByFile: [([String], [String])],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for (path, forbiddenPatterns) in forbiddenByFile {
            let normalized = try normalizedSource(at: path)
            for pattern in forbiddenPatterns {
                XCTAssertFalse(
                    normalized.contains(pattern),
                    "\(path.joined(separator: "/")) still contains \(pattern)",
                    file: file,
                    line: line
                )
            }
        }
    }

    func normalizedSource(
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
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}

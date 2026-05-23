import XCTest

final class SharedBridgeIconSourceTests: XCTestCase {
    func testSharedPlaceholderAndHeaderBridgesRenderThroughAppIcon() throws {
        let contentHeader = try normalizedSource(at: ["sideBar", "Design", "Components", "ContentHeaderRow.swift"])
        let placeholder = try normalizedSource(at: ["sideBar", "Views", "Common", "ContentViewComponents.swift"])
        let panelPlaceholder = try normalizedSource(
            at: ["sideBar", "Views", "Common", "SidebarPanelPlaceholder.swift"]
        )
        let sparseStateRow = try normalizedSource(
            at: ["sideBar", "Views", "Common", "SidebarSparseStateRow.swift"]
        )

        XCTAssertTrue(contentHeader.contains("init(icon:AppIcon,"))
        XCTAssertTrue(contentHeader.contains("Image(appIcon:icon)"))
        XCTAssertFalse(contentHeader.contains("init(iconName:String,"))
        XCTAssertFalse(contentHeader.contains("Image(systemName:iconName)"))

        XCTAssertTrue(placeholder.contains("publicleticon:AppIcon?"))
        XCTAssertTrue(placeholder.contains("Image(appIcon:icon)"))
        XCTAssertTrue(placeholder.contains("varappIcon:AppIcon{"))
        XCTAssertTrue(placeholder.contains("icon:resource.appIcon"))
        XCTAssertFalse(placeholder.contains("publicleticonName:String?"))
        XCTAssertFalse(placeholder.contains("Image(systemName:iconName)"))
        XCTAssertFalse(placeholder.contains("iconName:resource.iconName"))

        XCTAssertTrue(panelPlaceholder.contains("publicleticon:AppIcon?"))
        XCTAssertTrue(panelPlaceholder.contains("privatevarresolvedIcon:AppIcon?{"))
        XCTAssertTrue(panelPlaceholder.contains("Image(appIcon:icon)"))
        XCTAssertTrue(panelPlaceholder.contains("returnstyle==.error?AppIcon.State.warningFilled:nil"))
        XCTAssertFalse(panelPlaceholder.contains("publicleticonName:String?"))
        XCTAssertFalse(panelPlaceholder.contains("Image(systemName:icon)"))
        XCTAssertFalse(panelPlaceholder.contains("resolvedIconName"))

        XCTAssertTrue(sparseStateRow.contains("publicleticon:AppIcon"))
        XCTAssertTrue(sparseStateRow.contains("publicinit(icon:AppIcon,title:String,subtitle:String?=nil)"))
        XCTAssertTrue(sparseStateRow.contains("Image(appIcon:icon)"))
        XCTAssertFalse(sparseStateRow.contains("publicleticonName:String"))
        XCTAssertFalse(sparseStateRow.contains("Image(systemName:iconName)"))
    }

    func testCallSitesUseAppIconApisForSharedBridgeComponents() throws {
        let allSource = try source(at: ["sideBar"])
        let normalized = allSource.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("ContentHeaderRow(iconName:"))
        XCTAssertFalse(normalized.contains("PlaceholderView(title:emptyState.title,subtitle:emptyState.subtitle,iconName:"))
        let panelPlaceholderSearchBridge = "SidebarPanelPlaceholder(title:searchEmptyState.title,"
            + "subtitle:searchEmptyState.subtitle,iconName:"
        XCTAssertFalse(normalized.contains(panelPlaceholderSearchBridge))
        XCTAssertFalse(normalized.contains("SidebarSparseStateRow(iconName:"))

        let chatHeader = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatHeaderView.swift"])
        let notesDetail = try normalizedSource(at: ["sideBar", "Views", "Notes", "NotesDetailView.swift"])
        let tasksDetail = try normalizedSource(at: ["sideBar", "Views", "Tasks", "TasksDetailView.swift"])
        let largerTextQA = try normalizedSource(at: ["sideBar", "Views", "QA", "LargerTextQAMatrix.swift"])

        XCTAssertTrue(chatHeader.contains("ContentHeaderRow(icon:AppIcon.Domain.chat"))
        XCTAssertTrue(notesDetail.contains("ContentHeaderRow(icon:AppIcon.Domain.notes"))
        XCTAssertTrue(notesDetail.contains("icon:AppIcon.State.warning"))
        XCTAssertTrue(tasksDetail.contains("icon:emptyState.icon"))
        XCTAssertTrue(largerTextQA.contains("ContentHeaderRow(icon:AppIcon.Tasks.checklist"))
    }

    func testNotesPanelStaticIconsRouteThroughAppIcon() throws {
        let notesPanelComponents = try normalizedSource(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanelComponents.swift"]
        )
        let notesTreeArchive = try normalizedSource(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+TreeArchive.swift"]
        )
        let websitesPanel = try normalizedSource(at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel.swift"])
        let conversationsPanel = try normalizedSource(
            at: ["sideBar", "Views", "SidebarPanels", "ConversationsPanel.swift"]
        )

        XCTAssertTrue(
            notesPanelComponents.contains("Image(appIcon:item.isFile?AppIcon.Content.textDocument:AppIcon.Content.folder)")
        )
        XCTAssertTrue(
            notesPanelComponents.contains(
                "Image(appIcon:(isExpanded??false)?AppIcon.Navigation.chevronDown:AppIcon.Navigation.chevronRight)"
            )
        )
        XCTAssertFalse(notesPanelComponents.contains("Image(systemName:item.isFile?\"doc.text\":\"folder\")"))
        XCTAssertFalse(
            notesPanelComponents.contains("Image(systemName:(isExpanded??false)?\"chevron.down\":\"chevron.right\")")
        )

        XCTAssertTrue(notesTreeArchive.contains("SidebarSparseStateRow(icon:AppIcon.Content.note"))
        XCTAssertTrue(websitesPanel.contains("SidebarSparseStateRow(icon:AppIcon.Content.websiteFallback"))
        XCTAssertTrue(websitesPanel.contains("icon:searchEmptyState.icon"))
        XCTAssertTrue(conversationsPanel.contains("icon:searchEmptyState.icon"))
    }

    private func normalizedSource(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let source = try source(at: pathComponents, file: file, line: line)
        return source.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func source(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = pathComponents.reduce(sideBarRoot) { url, component in
            url.appendingPathComponent(component)
        }

        if FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: nil),
           !sourceURL.hasDirectoryPath {
            do {
                return try String(contentsOf: sourceURL, encoding: .utf8)
            } catch {
                XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
                throw error
            }
        }

        let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var contents = ""
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            contents += fileURL.lastPathComponent
            contents += "\n"
            contents += try String(contentsOf: fileURL, encoding: .utf8)
            contents += "\n"
        }
        return contents
    }
}

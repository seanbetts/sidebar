import XCTest

final class FileCategoryIconSourceTests: XCTestCase {
    func testFileCategoryAndMarkdownFallbackIconsRouteThroughAppIcon() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
        let ingestionRow = try normalizedSource(
            at: ["sideBar", "Views", "SidebarPanels", "FilesIngestionRow.swift"]
        )
        let filesPanel = try normalizedSource(at: ["sideBar", "Views", "SidebarPanels", "FilesPanel.swift"])
        let filesPanelHelpers = try normalizedSource(
            at: ["sideBar", "Views", "SidebarPanels", "FilesPanel+Helpers.swift"]
        )
        let panelData = try normalizedSource(
            at: ["sideBar", "ViewModels", "IngestionViewModel+PanelData.swift"]
        )
        let filesHeader = try normalizedSource(at: ["sideBar", "Views", "Files", "FilesHeaderComponents.swift"])
        let markdownUI = try normalizedSource(
            at: ["sideBar", "Views", "Common", "SideBarMarkdown+MarkdownUI.swift"]
        )
        let markdownGallery = try normalizedSource(
            at: ["sideBar", "Views", "Common", "SideBarMarkdown+Gallery.swift"]
        )
        let markdown = try normalizedSource(at: ["sideBar", "Views", "Common", "SideBarMarkdown.swift"])
        let selectableNoteRead = try normalizedSource(
            at: ["sideBar", "Views", "Notes", "SelectableNoteReadView.swift"]
        )

        XCTAssertTrue(appIcon.contains("publicstaticletrichTextDocument=AppIcon(rawValue:\"doc.richtext\")"))
        XCTAssertTrue(appIcon.contains("publicstaticlettable=AppIcon(rawValue:\"tablecells\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletreport=AppIcon(rawValue:\"chart.line.text.clipboard\")"))
        XCTAssertTrue(
            appIcon.contains("publicstaticletpresentation=AppIcon(rawValue:\"rectangle.on.rectangle.angled\")")
        )
        XCTAssertTrue(appIcon.contains("publicstaticletvideoFile=AppIcon(rawValue:\"video\")"))
        XCTAssertTrue(appIcon.contains("enumMarkdown{"))
        XCTAssertTrue(appIcon.contains("publicstaticlettaskCompleted=AppIcon(rawValue:\"checkmark.square.fill\")"))
        XCTAssertTrue(appIcon.contains("publicstaticlettaskIncomplete=AppIcon(rawValue:\"square\")"))

        XCTAssertTrue(ingestionRow.contains("importsideBarShared"))
        XCTAssertTrue(ingestionRow.contains("Image(appIcon:AppIcon.State.warningFilled)"))
        XCTAssertTrue(ingestionRow.contains("Image(appIcon:icon)"))
        XCTAssertTrue(ingestionRow.contains("privatevaricon:AppIcon{"))
        XCTAssertFalse(ingestionRow.contains("Image(systemName:\"exclamationmark.triangle.fill\")"))
        XCTAssertFalse(ingestionRow.contains("Image(systemName:iconName)"))

        XCTAssertTrue(filesPanel.contains("Image(appIcon:categoryIcon(category))"))
        XCTAssertTrue(
            filesPanel.contains("Image(appIcon:isExpanded?AppIcon.Navigation.chevronDown:AppIcon.Navigation.chevronRight)")
        )
        XCTAssertFalse(filesPanel.contains("Image(systemName:categoryIconName(category))"))
        XCTAssertFalse(filesPanel.contains("Image(systemName:isExpanded?\"chevron.down\":\"chevron.right\")"))

        XCTAssertTrue(filesPanelHelpers.contains("funccategoryIcon(_category:String)->AppIcon{"))
        XCTAssertTrue(panelData.contains("funcpanelCategoryIcon(_category:String)->AppIcon{"))
        XCTAssertTrue(filesHeader.contains("ContentHeaderRow(icon:icon,"))
        XCTAssertTrue(filesHeader.contains("privatevaricon:AppIcon{"))
        XCTAssertFalse(filesHeader.contains("ContentHeaderRow(iconName:iconName,"))

        XCTAssertTrue(markdownUI.contains("Image(appIcon:AppIcon.Content.photo)"))
        XCTAssertTrue(markdownGallery.contains("Image(appIcon:AppIcon.Content.photo)"))
        XCTAssertTrue(markdown.contains("Image(appIcon:AppIcon.Content.photo)"))
        XCTAssertTrue(
            markdown.contains(
                "Image(appIcon:configuration.isCompleted?AppIcon.Markdown.taskCompleted"
                    + ":AppIcon.Markdown.taskIncomplete)"
            )
        )
        XCTAssertFalse(markdownUI.contains("Image(systemName:\"photo\")"))
        XCTAssertFalse(markdownGallery.contains("Image(systemName:\"photo\")"))
        XCTAssertFalse(markdown.contains("Image(systemName:\"photo\")"))
        XCTAssertFalse(markdown.contains("\"checkmark.square.fill\""))
        XCTAssertFalse(markdown.contains("Image(systemName:configuration.isCompleted?"))
        XCTAssertTrue(
            selectableNoteRead.contains(
                "letappIcon:AppIcon=isChecked?AppIcon.Markdown.taskCompleted:AppIcon.Markdown.taskIncomplete"
            )
        )
        XCTAssertTrue(selectableNoteRead.contains("UIImage(appIcon:appIcon)"))
        XCTAssertTrue(selectableNoteRead.contains("NSImage(appIcon:appIcon"))
        XCTAssertFalse(selectableNoteRead.contains("\"checkmark.square.fill\""))
        XCTAssertFalse(selectableNoteRead.contains("systemSymbolName:isChecked?"))
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

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}

import XCTest

final class Task15ChromeStatusIconSourceTests: XCTestCase {
    func testChromeStatusAndNotesIconVocabularyExists() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])

        XCTAssertTrue(appIcon.contains("publicstaticletselectionCheck=AppIcon(rawValue:\"checkmark\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletmessageThread=AppIcon(rawValue:\"bubble.left.and.bubble.right\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletscratchpad=AppIcon(rawValue:\"square.and.pencil\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletchecklist=AppIcon(rawValue:\"checklist\")"))
        XCTAssertTrue(appIcon.contains("enumNotes{"))
        XCTAssertTrue(appIcon.contains("publicstaticletformatting=AppIcon(rawValue:\"textformat\")"))
    }

    func testChromeAndWebsiteSurfacesRouteIconsThroughAppIcon() throws {
        let formField = try normalizedSource(at: ["sideBar", "Design", "Components", "FormField.swift"])
        let chatView = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatView.swift"])
        let compactMoreHeader = try normalizedSource(
            at: ["sideBar", "Views", "ContentView+CompactMoreDestination.swift"]
        )
        let settingsAdditional = try normalizedSource(
            at: ["sideBar", "Views", "Settings", "SettingsSections+Additional.swift"]
        )
        let storeSkillDetail = try normalizedSource(
            at: ["sideBar", "Views", "SkillsStore", "StoreSkillDetailSheet.swift"]
        )
        let websiteDetail = try normalizedSource(at: ["sideBar", "Views", "Websites", "WebsitesDetailView.swift"])
        let websiteRows = try normalizedSource(at: ["sideBar", "Views", "SidebarPanels", "WebsiteRows.swift"])
        let faviconImage = try normalizedSource(at: ["sideBar", "Views", "Common", "FaviconImageView.swift"])

        XCTAssertTrue(formField.contains("Image(appIcon:AppIcon.Navigation.pickerDisclosure)"))
        XCTAssertFalse(formField.contains("Image(systemName:\"chevron.up.chevron.down\")"))

        XCTAssertTrue(chatView.contains("Image(appIcon:AppIcon.Action.add)"))
        XCTAssertFalse(chatView.contains("Image(systemName:\"plus\")"))

        XCTAssertTrue(compactMoreHeader.contains("Image(appIcon:AppIcon.Navigation.back)"))
        XCTAssertFalse(compactMoreHeader.contains("Image(systemName:\"chevron.left\")"))

        XCTAssertTrue(settingsAdditional.contains("Image(appIcon:AppIcon.Action.close)"))
        XCTAssertFalse(settingsAdditional.contains("Image(systemName:\"xmark\")"))
        XCTAssertTrue(storeSkillDetail.contains("Image(appIcon:AppIcon.Action.close)"))
        XCTAssertFalse(storeSkillDetail.contains("Image(systemName:\"xmark\")"))

        XCTAssertTrue(websiteDetail.contains("Image(appIcon:AppIcon.Content.websiteFallback)"))
        XCTAssertFalse(websiteDetail.contains("Image(systemName:\"globe\")"))
        XCTAssertTrue(faviconImage.contains("Image(appIcon:AppIcon.Content.websiteFallback)"))
        XCTAssertFalse(faviconImage.contains("Image(systemName:\"globe\")"))

        XCTAssertTrue(websiteRows.contains("varleadingIcon:AppIcon?{"))
        XCTAssertTrue(websiteRows.contains("Image(appIcon:leadingIcon)"))
        XCTAssertTrue(websiteRows.contains("Image(appIcon:AppIcon.State.retry)"))
        XCTAssertTrue(websiteRows.contains("Image(appIcon:AppIcon.Action.cancel)"))
        XCTAssertFalse(websiteRows.contains("varleadingIconName:String?{"))
        XCTAssertFalse(websiteRows.contains("Image(systemName:leadingIconName)"))
        XCTAssertFalse(websiteRows.contains("Image(systemName:\"arrow.counterclockwise.circle\")"))
        XCTAssertFalse(websiteRows.contains("Image(systemName:\"xmark.circle\")"))
    }

    func testSettingsNotesAndStatusSurfacesRouteIconsThroughAppIcon() throws {
        let queuedChanges = try normalizedSource(at: ["sideBar", "Views", "Settings", "QueuedChangesView.swift"])
        let soulCalibration = try normalizedSource(
            at: ["sideBar", "Views", "Chat", "SoulCalibrationPromptView.swift"]
        )
        let settingsMore = try normalizedSource(at: ["sideBar", "Views", "Settings", "SettingsMoreTabView.swift"])
        let scratchpad = try normalizedSource(at: ["sideBar", "Views", "Notes", "ScratchpadPopoverView.swift"])
        let morningDigest = try normalizedSource(
            at: ["sideBar", "Views", "MorningDigest", "MorningDigestView.swift"]
        )
        let formattingBar = try normalizedSource(at: ["sideBar", "Views", "Notes", "NoteFormattingBar.swift"])
        let notesComponents = try normalizedSource(at: ["sideBar", "Views", "Notes", "NotesViewComponents.swift"])

        XCTAssertTrue(queuedChanges.contains("systemImage:AppIcon.State.successCircle.rawValue"))
        XCTAssertTrue(queuedChanges.contains("Image(appIcon:appIcon)"))
        XCTAssertTrue(queuedChanges.contains("privatevarappIcon:AppIcon{"))
        XCTAssertTrue(queuedChanges.contains("returnAppIcon.Content.note"))
        XCTAssertTrue(queuedChanges.contains("returnAppIcon.Content.messageThread"))
        XCTAssertTrue(queuedChanges.contains("returnAppIcon.Content.websiteFallback"))
        XCTAssertTrue(queuedChanges.contains("returnAppIcon.Content.document"))
        XCTAssertTrue(queuedChanges.contains("returnAppIcon.Content.scratchpad"))
        XCTAssertTrue(queuedChanges.contains("returnAppIcon.State.syncing"))
        XCTAssertFalse(queuedChanges.contains("systemImage:\"checkmark.circle\""))
        XCTAssertFalse(queuedChanges.contains("Image(systemName:iconName)"))

        XCTAssertTrue(soulCalibration.contains("Image(appIcon:AppIcon.Settings.assistant)"))
        XCTAssertFalse(soulCalibration.contains("Image(systemName:\"brain.fill\")"))

        XCTAssertTrue(settingsMore.contains("systemImage:AppIcon.Domain.memories.rawValue"))
        XCTAssertFalse(settingsMore.contains("systemImage:\"bookmark\""))

        XCTAssertTrue(scratchpad.contains("Image(appIcon:AppIcon.State.warningFilled)"))
        XCTAssertFalse(scratchpad.contains("Image(systemName:\"exclamationmark.triangle.fill\")"))

        XCTAssertTrue(morningDigest.contains("systemImage:AppIcon.Tasks.checklist.rawValue"))
        XCTAssertFalse(morningDigest.contains("systemImage:\"checklist\""))

        XCTAssertTrue(formattingBar.contains("HeaderActionMenuControl(icon:AppIcon.Notes.formatting"))
        XCTAssertTrue(formattingBar.contains("systemImage:AppIcon.State.selectionCheck.rawValue"))
        XCTAssertFalse(formattingBar.contains("systemName:\"textformat\""))
        XCTAssertFalse(formattingBar.contains("systemImage:\"checkmark\""))

        XCTAssertTrue(notesComponents.contains("Image(appIcon:AppIcon.State.selectionCheck)"))
        XCTAssertFalse(notesComponents.contains("Image(systemName:\"checkmark\")"))
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

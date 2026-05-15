import XCTest

final class Task15AppIconSourceTests: XCTestCase {
    func testSharedAppIconVocabularyExistsWithCanonicalGroups() throws {
        let normalized = try source(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("publicstructAppIcon:RawRepresentable,Hashable,Sendable"))
        XCTAssertTrue(normalized.contains("publicletrawValue:String"))
        XCTAssertTrue(normalized.contains("publicextensionAppIcon{enumAction"))
        XCTAssertTrue(normalized.contains("publicstaticletadd=AppIcon(rawValue:\"plus\")"))
        XCTAssertTrue(normalized.contains("publicstaticletmore=AppIcon(rawValue:\"ellipsis\")"))
        XCTAssertTrue(normalized.contains("publicstaticletdelete=AppIcon(rawValue:\"trash\")"))
        XCTAssertTrue(normalized.contains("publicstaticletrefresh=AppIcon(rawValue:\"arrow.clockwise\")"))
        XCTAssertTrue(normalized.contains("enumDomain"))
        XCTAssertTrue(normalized.contains("publicstaticletchat=AppIcon(rawValue:\"bubble\")"))
        XCTAssertTrue(normalized.contains("publicstaticlettasks=AppIcon(rawValue:\"checkmark.square\")"))
        XCTAssertTrue(normalized.contains("publicstaticletmemoriesFilled=AppIcon(rawValue:\"bookmark.fill\")"))
        XCTAssertTrue(normalized.contains("publicstaticletexpandWorkspace=AppIcon(rawValue:\"arrow.up.right.and.arrow.down.left\")"))
        XCTAssertTrue(normalized.contains("publicstaticletcollapseWorkspace=AppIcon(rawValue:\"arrow.down.left.and.arrow.up.right\")"))
        XCTAssertTrue(normalized.contains("publicstaticletfolder=AppIcon(rawValue:\"folder\")"))
        XCTAssertTrue(normalized.contains("publicstaticlettaskList=AppIcon(rawValue:\"list.bullet.rectangle\")"))
        XCTAssertTrue(normalized.contains("publicstaticletinfoFilled=AppIcon(rawValue:\"info.circle.fill\")"))
        XCTAssertFalse(normalized.contains("publicenumAction"))
        XCTAssertFalse(normalized.contains("publicenumDomain"))
    }

    func testAppSectionRoutesIconsThroughAppIcon() throws {
        let normalized = try source(at: ["sideBar", "Models", "AppSection.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("publicvarappIcon:AppIcon{"))
        XCTAssertTrue(normalized.contains("publicvariconName:String{appIcon.rawValue}"))
        XCTAssertTrue(normalized.contains("returnAppIcon.Domain.chat"))
        XCTAssertTrue(normalized.contains("returnAppIcon.Domain.notes"))
        XCTAssertTrue(normalized.contains("returnAppIcon.Domain.tasks"))
        XCTAssertFalse(normalized.contains("return\"bubble\""))
        XCTAssertFalse(normalized.contains("return\"checkmark.square\""))
    }

    func testHeaderActionsExposeAppIconApiAndRenderThroughHelper() throws {
        let normalized = try source(at: ["sideBar", "Design", "Components", "HeaderActionIcon.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("init(appIcon:AppIcon){self.init(systemName:appIcon.rawValue)}"))
        XCTAssertTrue(normalized.contains("leticon:AppIcon"))
        XCTAssertTrue(normalized.contains("HeaderActionIcon(icon:icon)"))
        XCTAssertTrue(normalized.contains("Image(appIcon:icon)"))
        XCTAssertFalse(normalized.contains("HeaderActionIcon(systemName:systemName)"))
    }

    func testSidebarMenuItemFactoriesUseAppIcon() throws {
        let normalized = try source(at: ["sideBar", "Design", "Components", "SidebarMenuItem.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("leticon:AppIcon?"))
        XCTAssertTrue(normalized.contains("varsystemImage:String?{icon?.rawValue}"))
        XCTAssertTrue(normalized.contains("icon:isPinned?AppIcon.Action.unpin:AppIcon.Action.pin"))
        XCTAssertTrue(normalized.contains("AppIcon.Action.archive"))
        XCTAssertTrue(normalized.contains("icon:AppIcon.Action.delete"))
        XCTAssertFalse(normalized.contains("systemImage:\"trash\""))
        XCTAssertFalse(normalized.contains("systemImage:\"doc.on.doc\""))
    }

    func testSidebarPanelActionFactoriesUseAppIcon() throws {
        let normalized = try source(at: ["sideBar", "Design", "Components", "SidebarMenuItem.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("staticfuncnewTask(handler:@escaping()->Void)->SidebarMenuItem"))
        XCTAssertTrue(normalized.contains("title:\"Newtask\",icon:AppIcon.State.successCircle"))
        XCTAssertTrue(normalized.contains("staticfuncnewGroup(handler:@escaping()->Void)->SidebarMenuItem"))
        XCTAssertTrue(normalized.contains("title:\"Newgroup\",icon:AppIcon.Content.folder"))
        XCTAssertTrue(normalized.contains("staticfuncnewProject(handler:@escaping()->Void)->SidebarMenuItem"))
        XCTAssertTrue(normalized.contains("title:\"Newproject\",icon:AppIcon.Content.taskList"))
        XCTAssertTrue(normalized.contains("staticfuncrefresh(handler:@escaping()->Void)->SidebarMenuItem"))
        XCTAssertTrue(normalized.contains("title:\"Refresh\",icon:AppIcon.Action.refresh"))
        XCTAssertTrue(normalized.contains("staticfuncclose(handler:@escaping()->Void)->SidebarMenuItem"))
        XCTAssertTrue(normalized.contains("title:\"Close\",icon:AppIcon.Action.close"))
    }

    func testNotesAndFilesMenuActionSurfacesUseAppIconVocabulary() throws {
        try assertNoForbiddenIconPatterns([
            (
                ["sideBar", "Views", "Notes", "NotesDetailView+MenuActions.swift"],
                [
                    "systemImage:\"ellipsis\"",
                    "systemName:\"ellipsis\"",
                    "systemName:\"xmark\"",
                    "Label(\"Rename\",systemImage:\"pencil\")",
                    "Label(\"Move\",systemImage:\"arrow.forward.folder\")",
                    "Label(\"CopyText\",systemImage:\"doc.on.doc\")",
                    "Label(\"ShareText\",systemImage:\"square.and.arrow.up.on.square\")",
                    "Label(\"Download\",systemImage:\"square.and.arrow.down\")",
                    "Label(\"Delete\",systemImage:\"trash\")"
                ]
            ),
            (
                ["sideBar", "Views", "Notes", "NotesView.swift"],
                ["systemImage:\"ellipsis\""]
            ),
            (
                ["sideBar", "Views", "Files", "FilesHeaderActions.swift"],
                [
                    "systemName:\"ellipsis\"",
                    "systemImage:\"ellipsis\"",
                    "systemName:\"xmark\""
                ]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "FilesPanel+ContextMenu.swift"],
                ["systemImage:\"square.and.arrow.up\""]
            )
        ])
    }

    func testWebsiteMenuActionSurfacesUseAppIconVocabulary() throws {
        try assertNoForbiddenIconPatterns([
            (
                ["sideBar", "Views", "Websites", "WebsitesDetailView+MenuActions.swift"],
                [
                    "systemName:\"ellipsis\"",
                    "systemImage:\"ellipsis\""
                ]
            ),
            (
                ["sideBar", "Views", "Websites", "WebsitesView.swift"],
                ["systemImage:\"ellipsis\""]
            ),
            (
                ["sideBar", "Views", "Websites", "WebsitesDetailView.swift"],
                [
                    "systemName:\"xmark\"",
                    "systemName:expandButtonIconName",
                    "\"arrow.up.right.and.arrow.down.left\"",
                    "\"arrow.down.left.and.arrow.up.right\""
                ]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "WebsitesPanel.swift"],
                [
                    "systemName:\"plus\"",
                    "Label(\"Archive\",systemImage:\"archivebox\")",
                    "Image(systemName:isArchiveExpanded?\"chevron.down\":\"chevron.right\")"
                ]
            )
        ])
    }

    func testPanelAndWorkspaceActionSurfacesUseAppIconVocabulary() throws {
        try assertNoForbiddenIconPatterns([
            (
                ["sideBar", "Views", "SidebarPanels", "NotesPanel+TreeArchive.swift"],
                [
                    "Label(\"Archive\",systemImage:\"archivebox\")",
                    "Image(systemName:isArchiveExpanded?\"chevron.down\":\"chevron.right\")"
                ]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "TasksPanel+AddMenu.swift"],
                [
                    "systemName:\"plus\"",
                    "systemImage:\"plus\"",
                    "systemImage:\"checkmark.circle\"",
                    "systemImage:\"folder\"",
                    "systemImage:\"list.bullet.rectangle\""
                ]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "ConversationsPanelView+Helpers.swift"],
                ["systemName:\"plus\""]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "NotesPanel+Helpers.swift"],
                [
                    "systemName:\"folder\"",
                    "systemName:\"plus\""
                ]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "FilesPanel.swift"],
                [
                    "systemName:\"play.rectangle\"",
                    "systemName:\"plus\""
                ]
            ),
            (
                ["sideBar", "Views", "AgentWorkspace", "AgentWorkspaceSurfaceView.swift"],
                [
                    "systemName:\"arrow.clockwise\"",
                    "systemName:\"xmark\"",
                    "systemImage:\"arrow.clockwise\""
                ]
            ),
            (
                ["sideBar", "Views", "AgentWorkspace", "AgentWorkspaceSurfaceView+Helpers.swift"],
                [
                    "HeaderActionIcon(systemName:\"ellipsis\")",
                    "systemImage:\"ellipsis\""
                ]
            )
        ])

        let files = try source(at: ["sideBar", "Views", "SidebarPanels", "FilesPanel.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let expectedFilesEmptyState = [
            "EmptyStateContent.noContentYet(title:\"Nofilesyet\",",
            "subtitle:\"Uploadorcreateafiletogetstarted.\",",
            "icon:AppIcon.Domain.files)"
        ].joined()
        XCTAssertTrue(files.contains(expectedFilesEmptyState))

        let websites = try source(at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let expectedWebsitesEmptyState = [
            "EmptyStateContent.noContentYet(title:\"Nowebsitesyet\",",
            "subtitle:\"Savealinktogetstarted.\",",
            "icon:AppIcon.Domain.websites)"
        ].joined()
        XCTAssertTrue(websites.contains(expectedWebsitesEmptyState))

        let tasks = try source(at: ["sideBar", "Views", "Tasks", "TasksDetailView+EmptyState.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let expectedNoSelection = [
            "return.noSelection(title:\"Selectalist\",",
            "subtitle:\"Pickatasklistfromthesidebartogetstarted.\",",
            "icon:AppIcon.State.successCircle)"
        ].joined()
        XCTAssertTrue(tasks.contains(expectedNoSelection))
        XCTAssertTrue(
            tasks.contains("return.noContentYet(title:\"Nocompletedtasksyet\",icon:AppIcon.State.successCircle)")
        )
    }

    func testChatConversationActionsUseAppIconFactories() throws {
        let sidebarMenuItemSource = try source(at: ["sideBar", "Design", "Components", "SidebarMenuItem.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let chatHeaderSource = try source(at: ["sideBar", "Views", "Chat", "ChatHeaderView.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let conversationPanelSource = try source(
            at: ["sideBar", "Views", "SidebarPanels", "ConversationsPanelView+Helpers.swift"]
        )
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(sidebarMenuItemSource.contains("staticfuncshareTranscript(handler:@escaping()->Void)->SidebarMenuItem"))
        XCTAssertTrue(sidebarMenuItemSource.contains("title:\"ShareTranscript\",icon:AppIcon.Action.share"))
        XCTAssertTrue(sidebarMenuItemSource.contains("staticfuncexportTranscript(handler:@escaping()->Void)->SidebarMenuItem"))
        XCTAssertTrue(sidebarMenuItemSource.contains("title:\"ExportTranscript\",icon:AppIcon.Action.download"))

        XCTAssertTrue(chatHeaderSource.contains("HeaderActionIcon(icon:AppIcon.Action.more)"))
        XCTAssertTrue(chatHeaderSource.contains("HeaderActionMenuButton(icon:AppIcon.Action.more"))
        XCTAssertTrue(chatHeaderSource.contains("Image(appIcon:AppIcon.Action.more)"))
        XCTAssertTrue(chatHeaderSource.contains(".shareTranscript{"))
        XCTAssertTrue(chatHeaderSource.contains(".exportTranscript{"))
        XCTAssertFalse(chatHeaderSource.contains("systemName:\"ellipsis\""))
        XCTAssertFalse(chatHeaderSource.contains("systemImage:\"square.and.arrow.up\""))
        XCTAssertFalse(chatHeaderSource.contains("systemImage:\"square.and.arrow.down\""))

        XCTAssertTrue(conversationPanelSource.contains(".shareTranscript{"))
        XCTAssertTrue(conversationPanelSource.contains(".exportTranscript{"))
        XCTAssertFalse(conversationPanelSource.contains("systemImage:\"square.and.arrow.up\""))
        XCTAssertFalse(conversationPanelSource.contains("systemImage:\"square.and.arrow.down\""))
    }

    func testSkillIconResolverUsesAppIconVocabularyInternally() throws {
        let normalized = try source(at: ["sideBar", "Utilities", "SkillIconResolver.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("privatestaticletfallbackIcon=AppIcon.Skills.fallback"))
        XCTAssertTrue(normalized.contains("privatestaticletskillIcons:[String:AppIcon]"))
        XCTAssertTrue(normalized.contains("staticfuncappIcon(skillId:String?,iconKey:String?)->AppIcon"))
        XCTAssertTrue(normalized.contains("returnappIcon(skillId:skillId,iconKey:iconKey).rawValue"))
        XCTAssertTrue(normalized.contains("\"audio-transcribe\":AppIcon.Media.waveform"))
        XCTAssertFalse(normalized.contains("fallbackSystemName"))
        XCTAssertFalse(normalized.contains("skillSymbols:[String:String]"))
    }

    func testSharedEmptySearchStatusComponentsUseAppIconVocabulary() throws {
        try assertNoForbiddenIconPatterns([
            (
                ["sideBar", "Design", "Components", "EmptyStateContent.swift"],
                [
                    "systemImage:\"magnifyingglass\"",
                    "systemImage:\"checkmark.circle\""
                ]
            ),
            (
                ["sideBar", "Design", "Components", "EmptyStateView.swift"],
                ["Image(systemName:systemImage)"]
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

    func testFeatureLevelEmptyStatesUseAppIconVocabulary() throws {
        try assertNoForbiddenIconPatterns([
            (
                ["sideBar", "Views", "SidebarPanels", "FilesPanel.swift"],
                ["systemImage:\"folder\""]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "WebsitesPanel.swift"],
                ["systemImage:\"globe\""]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "NotesPanel+Helpers.swift"],
                ["systemImage:\"text.document\""]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "ConversationsPanel.swift"],
                ["systemImage:\"bubble\""]
            ),
            (
                ["sideBar", "Views", "Settings", "SettingsMoreTabView.swift"],
                [
                    "EmptyStateView(title:\"Nomemoriesyet\",subtitle:\"Memoriessavedfromyourchatsappearhere.\",systemImage:\"bookmark\")",
                    "EmptyStateView(title:\"Nomemoriesmatchthatsearch\",systemImage:\"magnifyingglass\")"
                ]
            ),
            (
                ["sideBar", "Views", "Settings", "MemoriesSettingsView.swift"],
                [
                    "EmptyStateView(title:\"Nomemoriesyet\",subtitle:\"Memoriessavedfromyourchatsappearhere.\",systemImage:\"bookmark\")",
                    "EmptyStateView(title:\"Nomemoriesmatchthatsearch\",systemImage:\"magnifyingglass\")"
                ]
            ),
            (
                ["sideBar", "Views", "Notes", "ScratchpadPopoverView.swift"],
                ["systemImage:\"square.and.pencil\""]
            ),
            (
                ["sideBar", "Views", "Tasks", "TasksDetailView+EmptyState.swift"],
                [
                    "systemImage:\"checkmark.circle\""
                ]
            )
        ])
    }

    func testMemoriesAndSkillsStoreChromeUseAppIconVocabulary() throws {
        let memoriesSource = try source(at: ["sideBar", "Views", "Settings", "MemoriesSettingsView.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let skillsStoreSource = try source(at: ["sideBar", "Views", "SkillsStore", "SkillsStoreDetailView.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let settingsMacSource = try source(at: ["sideBar", "Views", "Settings", "SettingsMacStyles.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let contentHeaderSource = try source(at: ["sideBar", "Design", "Components", "ContentHeaderRow.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let placeholderSource = try source(at: ["sideBar", "Views", "Common", "ContentViewComponents.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            memoriesSource.contains("icon:selection==item.id?AppIcon.Domain.memoriesFilled:AppIcon.Domain.memories")
        )
        XCTAssertTrue(memoriesSource.contains("Image(appIcon:AppIcon.Action.search)"))
        XCTAssertTrue(memoriesSource.contains("Image(appIcon:AppIcon.Action.clearFilled)"))
        XCTAssertTrue(memoriesSource.contains("icon:AppIcon.Domain.memories"))
        XCTAssertTrue(memoriesSource.contains("Image(appIcon:AppIcon.Domain.memories)"))
        XCTAssertFalse(memoriesSource.contains("systemImage:selection==item.id?\"bookmark.fill\":\"bookmark\""))
        XCTAssertFalse(memoriesSource.contains("Image(systemName:\"magnifyingglass\")"))
        XCTAssertFalse(memoriesSource.contains("Image(systemName:\"xmark.circle.fill\")"))
        XCTAssertFalse(memoriesSource.contains("iconName:\"bookmark\""))
        XCTAssertFalse(memoriesSource.contains("Image(systemName:\"bookmark\")"))

        XCTAssertTrue(settingsMacSource.contains("leticon:AppIcon"))
        XCTAssertTrue(settingsMacSource.contains("Image(appIcon:icon)"))

        XCTAssertTrue(contentHeaderSource.contains("init(icon:AppIcon,"))
        XCTAssertTrue(contentHeaderSource.contains("Image(appIcon:icon)"))
        XCTAssertTrue(placeholderSource.contains("icon:AppIcon?=nil"))
        XCTAssertTrue(placeholderSource.contains("Image(appIcon:icon)"))

        XCTAssertTrue(skillsStoreSource.contains("ContentHeaderRow(icon:AppIcon.Domain.skillsStore"))
        XCTAssertTrue(skillsStoreSource.contains("icon:AppIcon.State.warning"))
        XCTAssertTrue(skillsStoreSource.contains("icon:AppIcon.Action.search"))
        XCTAssertFalse(skillsStoreSource.contains("iconName:\"command.circle\""))
        XCTAssertFalse(skillsStoreSource.contains("iconName:\"exclamationmark.triangle\""))
        XCTAssertFalse(skillsStoreSource.contains("iconName:\"magnifyingglass\""))
    }

    private func assertNoForbiddenIconPatterns(
        _ forbiddenByFile: [([String], [String])],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for (path, forbiddenPatterns) in forbiddenByFile {
            let normalized = try source(at: path)
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
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

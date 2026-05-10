import XCTest

final class Task4SidebarChromeRegressionTests: XCTestCase {
    func testSidebarHoverModifierAvoidsCursorPushPopStackManagement() throws {
        let normalized = try source(
            at: ["sideBar", "Design", "Modifiers", "SidebarHoverModifier.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains(".push()"))
        XCTAssertFalse(normalized.contains("NSCursor.pop()"))
    }

    func testMacInputSurfaceUsesWhiteLightModeFill() throws {
        let normalized = try source(
            at: ["sideBar", "Views", "Common", "Color+Platform.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "staticletinput=makeDynamicNSColor(name:\"macosInput\",light:NSColor(srgbRed:1,green:1,blue:1,alpha:1)"
            )
        )
    }

    func testArchiveRowsUseXXLTopInsetWithoutHiddenHeaders() throws {
        let notes = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+TreeArchive.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let websites = try source(
            at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(notes.contains("top:DesignTokens.Spacing.xxl"))
        XCTAssertTrue(websites.contains("top:DesignTokens.Spacing.xxl"))
        XCTAssertFalse(notes.contains("sidebarHiddenProminentSectionHeader"))
        XCTAssertFalse(websites.contains("sidebarHiddenProminentSectionHeader"))
    }

    func testMacContentPanelsUseExplicitPlainListActivationPath() throws {
        let conversations = try source(
            at: ["sideBar", "Views", "SidebarPanels", "ConversationsPanelView+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let notes = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let files = try source(
            at: ["sideBar", "Views", "SidebarPanels", "FilesPanel+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let tasks = try source(
            at: ["sideBar", "Views", "SidebarPanels", "TasksPanel+Computed.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let tasksPanel = try source(
            at: ["sideBar", "Views", "SidebarPanels", "TasksPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let websites = try source(
            at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel+ListSections.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(conversations.contains("sidebarPanelList{content()}"))
        XCTAssertFalse(conversations.contains("sidebarPanelList(selection:conversationSelectionBinding){content()}"))
        XCTAssertFalse(conversations.contains(".tag(conversation.id)"))
        XCTAssertTrue(conversations.contains("return{Task{awaitviewModel.selectConversation(id:conversation.id)}}"))

        XCTAssertTrue(notes.contains("sidebarPanelList{content()}"))
        XCTAssertFalse(notes.contains("sidebarPanelList(selection:noteSelectionBinding){content()}"))
        XCTAssertFalse(notes.contains("row.tag(selectionID)"))
        XCTAssertFalse(notes.contains(".tag(node.path)"))

        XCTAssertTrue(files.contains("sidebarPanelList{content()}"))
        XCTAssertFalse(files.contains("sidebarPanelList(selection:fileSelectionBinding){content()}"))
        XCTAssertFalse(files.contains("#ifos(macOS)returnnil#else"))

        XCTAssertTrue(tasks.contains("sidebarPanelList{content()}"))
        XCTAssertFalse(tasks.contains("sidebarPanelList(selection:taskSelectionBinding){content()}"))
        XCTAssertFalse(tasksPanel.contains(".tag(selection)"))

        XCTAssertTrue(websites.contains("sidebarPanelList{content()}"))
        XCTAssertFalse(websites.contains("sidebarPanelList(selection:websiteSelectionBinding){content()}"))
        XCTAssertFalse(websites.contains("row.tag(item.id)"))
        XCTAssertTrue(websites.contains("return{open(item:item)}"))
    }

    func testSelectableRowAvoidsButtonBackedPrimaryActionChrome() throws {
        let normalized = try source(
            at: ["sideBar", "Design", "Components", "SelectableRow.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("Button(action:primaryAction)"))
        XCTAssertFalse(normalized.contains(".onTapGesture{primaryAction?()}"))
        XCTAssertTrue(normalized.contains("ifletprimaryAction"))
        XCTAssertTrue(normalized.contains(".contentShape(Rectangle())"))
    }

    func testMacSidebarPanelsUseSidebarListChromeAndSharedListWrapper() throws {
        let normalized = try source(
            at: ["sideBar", "Views", "SidebarPanels", "PanelComponents.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let selectionListSignature =
            "funcsidebarPanelList<SelectionValue:Hashable,Content:View>("
            + "selection:Binding<SelectionValue?>?=nil,@ViewBuildercontent:()->Content)"
            + "->someView"

        XCTAssertTrue(
            normalized.contains(selectionListSignature)
        )
        XCTAssertTrue(normalized.contains("funcsidebarPanelList<Content:View>(@ViewBuildercontent:()->Content)->someView"))
        XCTAssertTrue(normalized.contains("#ifos(macOS)self.listStyle(.sidebar)"))
        XCTAssertFalse(normalized.contains("#ifos(macOS)self.listStyle(.plain)"))
    }

    func testMacSelectableContentRowsUseExplicitPrimaryActions() throws {
        let notes = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanelComponents.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let files = try source(
            at: ["sideBar", "Views", "SidebarPanels", "FilesPanel+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let conversations = try source(
            at: ["sideBar", "Views", "SidebarPanels", "ConversationsPanelView+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let tasks = try source(
            at: ["sideBar", "Views", "SidebarPanels", "TasksPanelRows.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(notes.contains("#ifos(macOS)ifitem.isFile{returnnil}#endif"))
        XCTAssertFalse(files.contains("#ifos(macOS)returnnil#else"))
        XCTAssertFalse(conversations.contains("#ifos(macOS)nil#else"))
        XCTAssertFalse(tasks.contains("#ifos(macOS)nil#else"))
    }

    func testSelectableRowOwnsSidebarPanelRowBackgroundChrome() throws {
        let conversations = try source(
            at: ["sideBar", "Views", "SidebarPanels", "ConversationsPanelView+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let filesList = try source(
            at: ["sideBar", "Views", "SidebarPanels", "FilesPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let pinnedFiles = try source(
            at: ["sideBar", "Views", "SidebarPanels", "FilesPanel+PinnedReorder.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let notes = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+PinnedReorder.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let noteSearch = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let tasks = try source(
            at: ["sideBar", "Views", "SidebarPanels", "TasksPanelRows.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let websites = try source(
            at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel+ListSections.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(
            conversations.contains(
                ".listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected:viewModel.selectedConversationId==conversation.id))"
            )
        )
        XCTAssertFalse(filesList.contains(".listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected:isSelected))"))
        XCTAssertFalse(pinnedFiles.contains(".listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected:isSelected))"))
        XCTAssertFalse(notes.contains(".listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected:isSelected))"))
        XCTAssertFalse(noteSearch.contains(".tag(node.path)"))
        XCTAssertFalse(tasks.contains(".listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected:isSelected))"))
        XCTAssertFalse(websites.contains(".listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected:isSelected))"))
    }

    func testMacPinnedReorderRowsDoNotReintroduceSelectionTags() throws {
        let notes = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+PinnedReorder.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let files = try source(
            at: ["sideBar", "Views", "SidebarPanels", "FilesPanel+PinnedReorder.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(notes.contains("letbaseRow=NotesTreeRow("))
        XCTAssertFalse(notes.contains(".tag(item.id)"))
        XCTAssertFalse(files.contains(".tag(item.file.id)"))
    }

    func testSearchableSidebarHeadersPinMinHeightToTopAlignment() throws {
        let conversations = try source(
            at: ["sideBar", "Views", "SidebarPanels", "ConversationsPanelView+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let notes = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let files = try source(
            at: ["sideBar", "Views", "SidebarPanels", "FilesPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let tasks = try source(
            at: ["sideBar", "Views", "SidebarPanels", "TasksPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let websites = try source(
            at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let expectedFrame =
            ".frame(maxWidth:.infinity,minHeight:"
            + "LayoutMetrics.searchablePanelHeaderMinHeight("
            + "showsInlineSearch:showsInlineSearch),alignment:.top)"

        XCTAssertTrue(conversations.contains(expectedFrame))
        XCTAssertTrue(notes.contains(expectedFrame))
        XCTAssertTrue(files.contains(expectedFrame))
        XCTAssertTrue(tasks.contains(expectedFrame))
        XCTAssertTrue(websites.contains(expectedFrame))
    }

    func testSearchableSidebarHeadersReserveStableTitleRowHeight() throws {
        let conversations = try source(
            at: ["sideBar", "Views", "SidebarPanels", "ConversationsPanelView+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let notes = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let files = try source(
            at: ["sideBar", "Views", "SidebarPanels", "FilesPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let tasks = try source(
            at: ["sideBar", "Views", "SidebarPanels", "TasksPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let websites = try source(
            at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let expectedHeader =
            "PanelHeader(title:\"Chat\",minimumContentHeight:HeaderActionControlMetrics.chromeHeight)"
        let expectedNotesHeader =
            "PanelHeader(title:\"Notes\",minimumContentHeight:HeaderActionControlMetrics.chromeHeight)"
        let expectedFilesHeader =
            "PanelHeader(title:\"Files\",minimumContentHeight:HeaderActionControlMetrics.chromeHeight)"
        let expectedTasksHeader =
            "PanelHeader(title:\"Tasks\",minimumContentHeight:HeaderActionControlMetrics.chromeHeight)"
        let expectedWebsitesHeader =
            "PanelHeader(title:\"Websites\",minimumContentHeight:HeaderActionControlMetrics.chromeHeight)"

        XCTAssertTrue(conversations.contains(expectedHeader))
        XCTAssertTrue(notes.contains(expectedNotesHeader))
        XCTAssertTrue(files.contains(expectedFilesHeader))
        XCTAssertTrue(tasks.contains(expectedTasksHeader))
        XCTAssertTrue(websites.contains(expectedWebsitesHeader))
    }

    func testPanelHeaderAppliesMinHeightBeforePadding() throws {
        let panelHeader = try source(
            at: ["sideBar", "Design", "Components", "PanelHeader.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            panelHeader.contains(
                "content.frame(minHeight:minimumContentHeight,alignment:.center)"
                    + ".padding(.horizontal,DesignTokens.Spacing.md)"
                    + ".padding(.vertical,DesignTokens.Spacing.sm)"
            )
        )
        XCTAssertFalse(
            panelHeader.contains(
                "content.padding(.horizontal,DesignTokens.Spacing.md)"
                    + ".padding(.vertical,DesignTokens.Spacing.sm)"
                    + ".frame(minHeight:minimumContentHeight,alignment:.center)"
            )
        )
    }

    func testSettingsEditorsUseSharedInputChrome() throws {
        let systemMac = try source(
            at: ["sideBar", "Views", "Settings", "SettingsSections+SystemMac.swift"]
        )
        let userSettings = try source(
            at: ["sideBar", "Views", "Settings", "SettingsSections+System.swift"]
        )

        XCTAssertTrue(systemMac.contains(".sidebarTextEntrySurface()"))
        XCTAssertFalse(systemMac.contains(".fill(.clear)"))
        XCTAssertTrue(userSettings.contains("SettingsIOSPlainTextEditor"))
    }

    func testMacSettingsSelectorsUseSharedMenuTriggersInsteadOfWrappedNativeControls() throws {
        let formField = try source(
            at: ["sideBar", "Design", "Components", "FormField.swift"]
        )
        let profileSupport = try source(
            at: ["sideBar", "Views", "Settings", "SettingsSections+ProfileSupport.swift"]
        )
        let profileMenu = try source(
            at: ["sideBar", "Views", "Settings", "ProfileStringSelectorMenu.swift"]
        )
        let systemMac = try source(
            at: ["sideBar", "Views", "Settings", "SettingsSections+SystemMac.swift"]
        )

        XCTAssertTrue(formField.contains("struct SidebarSelectionMenu"))
        XCTAssertTrue(profileMenu.contains("SidebarSelectionMenu"))
        XCTAssertTrue(systemMac.contains("SidebarSelectionMenu"))
        XCTAssertFalse(profileSupport.contains(".pickerStyle(.menu)"))
        XCTAssertFalse(systemMac.contains(".pickerStyle(.menu)"))
    }

    func testMacSettingsSelectorTriggerUsesControlSizedTypography() throws {
        let normalized = try source(
            at: ["sideBar", "Design", "Components", "FormField.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Text(title).appFont(.subheading)"))
        XCTAssertFalse(normalized.contains("Text(title).appFont(.body)"))
    }

    func testMacDateOfBirthUsesPopoverTriggerInsteadOfWrappedInlineDatePicker() throws {
        let dateOfBirth = try source(
            at: ["sideBar", "Views", "Settings", "ProfileDateOfBirthField.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(dateOfBirth.contains(".popover("))
        XCTAssertFalse(
            dateOfBirth.contains(
                "DatePicker(\"DateofBirth\",selection:$dateOfBirth,displayedComponents:.date)"
                    + ".labelsHidden().appFont(.body).sidebarTextEntryControl()"
            )
        )
    }

    private func source(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let root = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = pathComponents.reduce(root) { partial, component in
            partial.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(sourceURL.lastPathComponent): \(error)", file: file, line: line)
            throw error
        }
    }
}

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
        XCTAssertTrue(normalized.contains("enumDomain"))
        XCTAssertTrue(normalized.contains("publicstaticletchat=AppIcon(rawValue:\"bubble\")"))
        XCTAssertTrue(normalized.contains("publicstaticlettasks=AppIcon(rawValue:\"checkmark.square\")"))
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

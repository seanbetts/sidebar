import XCTest

final class WorkspaceTargetIconSourceTests: XCTestCase {
    func testWorkspaceTargetParserUsesAppIconVocabulary() throws {
        let parserSource = try source(at: ["sideBar", "ViewModels", "Chat", "ToolResultWorkspaceSurfaceParser.swift"])
            .normalizedForSourceAssertions()
        let appIconSource = try source(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
            .normalizedForSourceAssertions()
        let detailCardsSource = try source(at: ["sideBar", "Views", "Chat", "ChatToolDetailCards.swift"])
            .normalizedForSourceAssertions()
        let scrollSupportSource = try source(at: ["sideBar", "Views", "Chat", "ChatMessageListScrollSupport.swift"])
            .normalizedForSourceAssertions()
        let agentWorkspaceSource = try source(at: ["sideBar", "Views", "AgentWorkspace", "AgentWorkspaceSurfaceView.swift"])
            .normalizedForSourceAssertions()
        let agentWorkspaceHelpersSource = try source(at: ["sideBar", "Views", "AgentWorkspace", "AgentWorkspaceSurfaceView+Helpers.swift"])
            .normalizedForSourceAssertions()

        XCTAssertTrue(appIconSource.contains("enumWorkspace{"))
        XCTAssertTrue(appIconSource.contains("publicstaticletsurface=AppIcon(rawValue:\"rectangle.on.rectangle\")"))
        XCTAssertTrue(appIconSource.contains("publicstaticletopenEntityFallback=AppIcon(rawValue:\"arrow.up.forward.app\")"))
        XCTAssertTrue(appIconSource.contains("publicstaticletmarkdownSurface=AppIcon(rawValue:\"doc.plaintext\")"))
        XCTAssertTrue(appIconSource.contains("publicstaticlettableSurface=AppIcon(rawValue:\"tablecells\")"))
        XCTAssertTrue(appIconSource.contains("publicstaticletchartSurface=AppIcon(rawValue:\"chart.bar.xaxis\")"))
        XCTAssertTrue(appIconSource.contains("publicstaticletmapSurface=AppIcon(rawValue:\"map\")"))
        XCTAssertTrue(appIconSource.contains("publicstaticletformSurface=AppIcon(rawValue:\"list.bullet.clipboard\")"))
        XCTAssertTrue(appIconSource.contains("publicstaticletactionPanelSurface=AppIcon(rawValue:\"slider.horizontal.3\")"))

        XCTAssertTrue(parserSource.contains("letappIcon:AppIcon"))
        XCTAssertFalse(parserSource.contains("variconName:String"))
        XCTAssertTrue(parserSource.contains("SkillIconResolver.appIcon(for:toolCall)"))
        XCTAssertTrue(parserSource.contains("appIcon:AppIcon.Workspace.surface"))
        XCTAssertTrue(parserSource.contains("returnAppIcon.Content.textDocument"))
        XCTAssertTrue(parserSource.contains("returnAppIcon.Domain.websites"))
        XCTAssertTrue(parserSource.contains("returnAppIcon.Domain.files"))
        XCTAssertTrue(parserSource.contains("returnAppIcon.Domain.chat"))
        XCTAssertTrue(parserSource.contains("returnAppIcon.Action.compose"))
        XCTAssertTrue(parserSource.contains("returnAppIcon.Domain.tasks"))
        XCTAssertTrue(parserSource.contains("returnAppIcon.Workspace.openEntityFallback"))

        XCTAssertFalse(parserSource.contains("iconName:\"rectangle.on.rectangle\""))
        XCTAssertFalse(parserSource.contains("return\"doc.text\""))
        XCTAssertFalse(parserSource.contains("return\"globe\""))
        XCTAssertFalse(parserSource.contains("return\"folder\""))
        XCTAssertFalse(parserSource.contains("return\"bubble.left\""))
        XCTAssertFalse(parserSource.contains("return\"square.and.pencil\""))
        XCTAssertFalse(parserSource.contains("return\"checkmark.square\""))
        XCTAssertFalse(parserSource.contains("return\"arrow.up.forward.app\""))

        XCTAssertTrue(detailCardsSource.contains("systemImage:target.appIcon.rawValue"))
        XCTAssertFalse(detailCardsSource.contains("systemImage:target.iconName"))

        XCTAssertTrue(scrollSupportSource.contains("$0.appIcon.rawValue"))
        XCTAssertFalse(scrollSupportSource.contains("$0.iconName"))

        XCTAssertTrue(agentWorkspaceSource.contains("ContentHeaderRow(icon:appIcon(for:surface.surfaceType)"))
        XCTAssertFalse(agentWorkspaceSource.contains("ContentHeaderRow(iconName:iconName(for:surface.surfaceType)"))
        XCTAssertTrue(agentWorkspaceHelpersSource.contains("funcappIcon(fortype:AgentWorkspaceSurfaceType)->AppIcon"))
        XCTAssertTrue(agentWorkspaceHelpersSource.contains("returnAppIcon.Workspace.markdownSurface"))
        XCTAssertTrue(agentWorkspaceHelpersSource.contains("returnAppIcon.Workspace.tableSurface"))
        XCTAssertTrue(agentWorkspaceHelpersSource.contains("returnAppIcon.Workspace.chartSurface"))
        XCTAssertTrue(agentWorkspaceHelpersSource.contains("returnAppIcon.Workspace.mapSurface"))
        XCTAssertTrue(agentWorkspaceHelpersSource.contains("returnAppIcon.Workspace.formSurface"))
        XCTAssertTrue(agentWorkspaceHelpersSource.contains("returnAppIcon.Workspace.actionPanelSurface"))
        XCTAssertFalse(agentWorkspaceHelpersSource.contains("return\"doc.plaintext\""))
        XCTAssertFalse(agentWorkspaceHelpersSource.contains("return\"tablecells\""))
        XCTAssertFalse(agentWorkspaceHelpersSource.contains("return\"chart.bar.xaxis\""))
        XCTAssertFalse(agentWorkspaceHelpersSource.contains("return\"map\""))
        XCTAssertFalse(agentWorkspaceHelpersSource.contains("return\"list.bullet.clipboard\""))
        XCTAssertFalse(agentWorkspaceHelpersSource.contains("return\"slider.horizontal.3\""))
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

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

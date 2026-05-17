import XCTest

final class Task15DynamicIconBoundarySourceTests: XCTestCase {
    func testDynamicSwiftUIIconBoundariesRenderThroughAppIconAdapters() throws {
        let skillIconView = try normalizedSource(at: ["sideBar", "Views", "Common", "SkillIconView.swift"])
        let settingsMac = try normalizedSource(at: ["sideBar", "Views", "Settings", "SettingsMacStyles.swift"])
        let workspaceModels = try normalizedSource(at: ["sideBar", "App", "WorkspaceModels.swift"])
        let workspacePayloadModels = try normalizedSource(at: ["sideBar", "App", "WorkspaceSurfacePayloadModels.swift"])
        let agentWorkspace = try normalizedSource(
            at: ["sideBar", "Views", "AgentWorkspace", "AgentWorkspaceSurfaceView+Helpers.swift"]
        )

        XCTAssertTrue(skillIconView.contains("leticon:AppIcon"))
        XCTAssertTrue(skillIconView.contains("letappIcon:AppIcon"))
        XCTAssertTrue(skillIconView.contains("Image(appIcon:icon)"))
        XCTAssertTrue(skillIconView.contains("SkillSymbolIcon(appIcon:appIcon"))
        XCTAssertFalse(skillIconView.contains("systemName:String"))
        XCTAssertFalse(skillIconView.contains("self.icon=AppIcon(rawValue:systemName)"))
        XCTAssertFalse(skillIconView.contains("SkillSymbolIcon(systemName:"))
        XCTAssertFalse(skillIconView.contains("Image(systemName:systemName)"))

        XCTAssertTrue(settingsMac.contains("leticon:AppIcon"))
        XCTAssertTrue(settingsMac.contains("Image(appIcon:icon)"))
        XCTAssertFalse(settingsMac.contains("letsystemImage:String?"))
        XCTAssertFalse(settingsMac.contains("Image(appIcon:AppIcon(rawValue:systemImage))"))
        XCTAssertFalse(settingsMac.contains("Image(systemName:systemImage)"))

        XCTAssertTrue(workspaceModels.contains("publicletappIcon:AppIcon?"))
        XCTAssertTrue(workspaceModels.contains("appIcon:AppIcon?=nil"))
        XCTAssertFalse(workspaceModels.contains("publicletsystemImage:String?"))
        XCTAssertTrue(workspacePayloadModels.contains("appIcon:systemImage.map(AppIcon.init(rawValue:))"))

        XCTAssertTrue(agentWorkspace.contains("ifletappIcon=action.appIcon"))
        XCTAssertTrue(agentWorkspace.contains("Image(appIcon:appIcon)"))
        XCTAssertFalse(agentWorkspace.contains("Image(appIcon:AppIcon(rawValue:systemImage))"))
        XCTAssertFalse(agentWorkspace.contains("Image(systemName:systemImage)"))
    }

    func testUIKitDynamicIconBoundariesRenderThroughAppIconAdapters() throws {
        let headerActionIcon = try normalizedSource(at: ["sideBar", "Design", "Components", "HeaderActionIcon.swift"])
        let shortcuts = try normalizedSource(at: ["sideBar", "App", "AppLaunchDelegate+Shortcuts.swift"])
        let uiKitFormattingPopover = try normalizedSource(
            at: ["sideBar", "Views", "Notes", "UIKitNoteFormattingPopoverView.swift"]
        )
        let appKitFormattingPopover = try normalizedSource(
            at: ["sideBar", "Views", "Notes", "AppKitNoteFormattingPopoverView.swift"]
        )

        XCTAssertTrue(headerActionIcon.contains("convenienceinit?(appIcon:AppIcon)"))
        XCTAssertTrue(headerActionIcon.contains("self.init(systemName:appIcon.rawValue)"))
        XCTAssertTrue(shortcuts.contains("guardletappIcon=appIcon(for:shortcut)else{returnnil}"))
        XCTAssertTrue(shortcuts.contains("returnUIImage(appIcon:appIcon)"))
        XCTAssertTrue(shortcuts.contains("funcappIcon(forshortcut:KeyboardShortcut)->AppIcon?"))
        XCTAssertTrue(shortcuts.contains("staticletsectionIcons:[AppSection:AppIcon]"))
        XCTAssertTrue(shortcuts.contains("staticletlistDirectionIcons:[ShortcutListDirection:AppIcon]"))
        XCTAssertTrue(shortcuts.contains("staticletactionIcons:[ShortcutAction:AppIcon]"))
        XCTAssertTrue(uiKitFormattingPopover.contains("letappIcon:AppIcon"))
        XCTAssertTrue(uiKitFormattingPopover.contains("pillButtonConfiguration(appIcon:item.appIcon"))
        XCTAssertTrue(uiKitFormattingPopover.contains("UIImage(appIcon:appIcon)"))
        XCTAssertTrue(appKitFormattingPopover.contains("letappIcon:AppIcon"))
        XCTAssertTrue(appKitFormattingPopover.contains("NSImage(appIcon:item.appIcon"))
        XCTAssertFalse(shortcuts.contains("symbolName(forshortcut:KeyboardShortcut)"))
        XCTAssertFalse(shortcuts.contains("sectionSymbolNames:[AppSection:String]"))
        XCTAssertFalse(shortcuts.contains("listDirectionSymbols:[ShortcutListDirection:String]"))
        XCTAssertFalse(shortcuts.contains("actionSymbolNames:[ShortcutAction:String]"))
        XCTAssertFalse(shortcuts.contains("UIImage(appIcon:AppIcon(rawValue:symbolName))"))
        XCTAssertFalse(shortcuts.contains("UIImage(systemName:symbolName)"))
        XCTAssertFalse(uiKitFormattingPopover.contains("letsymbol:String"))
        XCTAssertFalse(uiKitFormattingPopover.contains("UIImage(appIcon:AppIcon(rawValue:symbol))"))
        XCTAssertFalse(uiKitFormattingPopover.contains("UIImage(systemName:symbol)"))
        XCTAssertFalse(appKitFormattingPopover.contains("letsymbol:String"))
        XCTAssertFalse(appKitFormattingPopover.contains("systemSymbolName:item.symbol"))
    }

    func testProductionIconRenderingHasNoDirectImageSystemNameBoundaries() throws {
        let forbiddenByFile: [([String], [String])] = [
            (
                ["sideBar", "Views", "Common", "SkillIconView.swift"],
                [
                    "Image(systemName:systemName)",
                    "self.icon=AppIcon(rawValue:systemName)",
                    "SkillSymbolIcon(systemName:"
                ]
            ),
            (
                ["sideBar", "Views", "Settings", "SettingsMacStyles.swift"],
                [
                    "Image(systemName:systemImage)",
                    "Image(appIcon:AppIcon(rawValue:systemImage))"
                ]
            ),
            (
                ["sideBar", "Views", "AgentWorkspace", "AgentWorkspaceSurfaceView+Helpers.swift"],
                ["Image(systemName:systemImage)"]
            ),
            (
                ["sideBar", "App", "AppLaunchDelegate+Shortcuts.swift"],
                [
                    "UIImage(systemName:symbolName)",
                    "UIImage(appIcon:AppIcon(rawValue:symbolName))",
                    "sectionSymbolNames:[AppSection:String]",
                    "listDirectionSymbols:[ShortcutListDirection:String]",
                    "actionSymbolNames:[ShortcutAction:String]"
                ]
            ),
            (
                ["sideBar", "Views", "Notes", "UIKitNoteFormattingPopoverView.swift"],
                [
                    "UIImage(systemName:symbol)",
                    "UIImage(appIcon:AppIcon(rawValue:symbol))",
                    "letsymbol:String"
                ]
            ),
            (
                ["sideBar", "Views", "Notes", "AppKitNoteFormattingPopoverView.swift"],
                [
                    "systemSymbolName:item.symbol",
                    "letsymbol:String"
                ]
            )
        ]

        for (path, forbiddenPatterns) in forbiddenByFile {
            let normalized = try normalizedSource(at: path)
            for pattern in forbiddenPatterns {
                XCTAssertFalse(normalized.contains(pattern), "\(path.joined(separator: "/")) still contains \(pattern)")
            }
        }
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

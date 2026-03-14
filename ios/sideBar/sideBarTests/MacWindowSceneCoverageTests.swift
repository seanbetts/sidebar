import XCTest

final class MacWindowSceneCoverageTests: XCTestCase {
    func testMacAppUsesSingletonMainWindowSceneWithoutSeparateSettingsScene() throws {
        let normalized = try sideBarAppSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "Window(MacWindowConfiguration.mainWindowTitle,id:MacWindowConfiguration.mainWindowID){rootContentView}"
            )
        )
        XCTAssertTrue(normalized.contains("CommandGroup(replacing:.newItem){}"))
        XCTAssertFalse(normalized.contains("Settings{"))
    }

    func testSignedInContentHostsMacSettingsModal() throws {
        let normalized = try signedInContentSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("ifnewValue==.settings{"))
        XCTAssertTrue(normalized.contains("environment.commandSelection=nil"))
        XCTAssertTrue(normalized.contains("environment.isMacSettingsPresented"))
        XCTAssertTrue(normalized.contains("SettingsView(presentationStyle:.macModal"))
    }

    func testSettingsViewDefinesDedicatedMacModalPresentationChrome() throws {
        let normalized = try settingsViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("enumSettingsPresentationStyle"))
        XCTAssertTrue(normalized.contains("casemacModal"))
        XCTAssertTrue(normalized.contains("MacModalShell(type:settingsMacPresentationPanelType())"))
        XCTAssertTrue(normalized.contains("settingsInspectorHeader"))
        XCTAssertTrue(normalized.contains("settingsSidebarHeader"))
        XCTAssertTrue(normalized.contains("inlineSaveStatusView"))
        XCTAssertTrue(normalized.contains("Settings"))
        XCTAssertTrue(normalized.contains("Image(systemName:\"xmark.circle.fill\")"))
        XCTAssertFalse(normalized.contains("Button(\"Done\""))
    }

    func testMacSettingsEntryPointsRouteThroughInAppPresenter() throws {
        let sidebarRail = try sidebarRailSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let appCommands = try appCommandsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(sidebarRail.contains("SettingsLink{"))
        XCTAssertTrue(sidebarRail.contains("action:{onShowSettings?()}"))
        XCTAssertTrue(appCommands.contains("CommandGroup(replacing:.appSettings){"))
        XCTAssertTrue(appCommands.contains("environment.presentMacSettings()"))
        XCTAssertTrue(appCommands.contains("keyboardShortcut(\",\",modifiers:[.command])"))
        XCTAssertTrue(appCommands.contains("ifenvironment.isMacSettingsPresented{"))
        XCTAssertTrue(appCommands.contains("Button(\"CloseSettings\")"))
    }

    func testMacAppDisablesAutomaticWindowTabbing() throws {
        let normalized = try macAppDelegateSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("NSWindow.allowsAutomaticWindowTabbing=false"))
    }
}

private func sideBarAppSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("sideBarApp.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read sideBarApp.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func macAppDelegateSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("App")
        .appendingPathComponent("MacAppDelegate.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read MacAppDelegate.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func signedInContentSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("ContentView+SignedIn.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read ContentView+SignedIn.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func settingsViewSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Settings")
        .appendingPathComponent("SettingsView.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SettingsView.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func sidebarRailSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SidebarRail.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SidebarRail.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func appCommandsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("AppCommands.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read AppCommands.swift: \(error)", file: file, line: line)
        throw error
    }
}

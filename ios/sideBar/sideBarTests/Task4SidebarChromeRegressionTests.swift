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

    func testArchiveRowDoesNotUseExtraTallTopInset() throws {
        let normalized = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanel+TreeArchive.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("top:DesignTokens.Spacing.xxl"))
    }

    func testWebsitesArchiveRowDoesNotUseExtraTallTopInset() throws {
        let normalized = try source(
            at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("top:DesignTokens.Spacing.xxl"))
    }

    func testWebsitesPanelAvoidsSystemListSelectionAndUsesExplicitRowAction() throws {
        let normalized = try source(
            at: ["sideBar", "Views", "SidebarPanels", "WebsitesPanel+ListSections.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("List(selection:$selection)"))
        XCTAssertFalse(normalized.contains("#ifos(macOS)nil#else{open(item:item)}#endif"))
    }

    func testSelectableRowAvoidsButtonBackedPrimaryActionChrome() throws {
        let normalized = try source(
            at: ["sideBar", "Design", "Components", "SelectableRow.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("Button(action:primaryAction)"))
        XCTAssertFalse(normalized.contains(".onTapGesture{primaryAction?()}"))
        XCTAssertTrue(normalized.contains("ifletprimaryAction"))
    }

    func testMacSidebarPanelsUsePlainListStyleForFullWidthSelectionChrome() throws {
        let normalized = try source(
            at: ["sideBar", "Views", "SidebarPanels", "PanelComponents.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("#ifos(macOS)self.listStyle(.plain)"))
        XCTAssertFalse(normalized.contains("#ifos(macOS)self.listStyle(.sidebar)"))
    }

    func testMacFileAndNoteRowsUseExplicitPrimaryActions() throws {
        let notes = try source(
            at: ["sideBar", "Views", "SidebarPanels", "NotesPanelComponents.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let files = try source(
            at: ["sideBar", "Views", "SidebarPanels", "FilesPanel+Helpers.swift"]
        ).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(notes.contains("#ifos(macOS)returnnil#elsereturnonSelect#endif"))
        XCTAssertFalse(files.contains("#ifos(macOS)returnnil#elsereturn{open(item:item)}#endif"))
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

        XCTAssertTrue(normalized.contains("Text(title).appFont(.subheadline)"))
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

import XCTest
@testable import sideBar

final class AppCommandsTests: XCTestCase {
    func testMacSectionCommandContextPrefersFocusedSectionAndFiltersUnsupportedSections() {
        XCTAssertEqual(
            SidebarCommands.macSectionCommandContext(focusedSection: .notes, activeSection: .tasks),
            .notes
        )
        XCTAssertEqual(
            SidebarCommands.macSectionCommandContext(focusedSection: nil, activeSection: .files),
            .files
        )
        XCTAssertEqual(
            SidebarCommands.macSectionCommandContext(focusedSection: .settings, activeSection: .tasks),
            .tasks
        )
        XCTAssertNil(
            SidebarCommands.macSectionCommandContext(focusedSection: .settings, activeSection: .skillsStore)
        )
    }

    func testMacFormatMenuFlattensNotesFormattingCommands() throws {
        let normalized = try normalizedAppCommandsSource()

        XCTAssertTrue(normalized.contains("CommandMenu(\"Format\")"))
        XCTAssertFalse(normalized.contains("Menu(\"TextStyle\")"))
        XCTAssertFalse(normalized.contains("Menu(\"Inline\")"))

        XCTAssertTrue(
            normalized.contains("Button(\"Title\"){environment.notesRuntime.editorViewModel.setTextStyle(.title)}")
        )
        XCTAssertTrue(
            normalized.contains("Button(\"Heading\"){environment.notesRuntime.editorViewModel.setTextStyle(.heading)}")
        )
        XCTAssertTrue(
            normalized.contains("Button(\"Subheading\"){environment.notesRuntime.editorViewModel.setTextStyle(.subheading)}")
        )
        XCTAssertTrue(
            normalized.contains("Button(\"Body\"){environment.notesRuntime.editorViewModel.setTextStyle(.body)}")
        )

        XCTAssertTrue(normalized.contains("Toggle(\"Bold\",isOn:formattingBinding(.bold))"))
        XCTAssertTrue(normalized.contains("Toggle(\"Italic\",isOn:formattingBinding(.italic))"))
        XCTAssertTrue(normalized.contains("Toggle(\"Underline\",isOn:formattingBinding(.underline))"))
        XCTAssertTrue(normalized.contains("Toggle(\"Strikethrough\",isOn:formattingBinding(.strikethrough))"))
        XCTAssertTrue(normalized.contains("Toggle(\"InlineCode\",isOn:formattingBinding(.inlineCode))"))
    }

    func testMacFormatMenuPreservesNotesFormattingShortcuts() throws {
        let normalized = try normalizedAppCommandsSource()
        let editor = "environment.notesRuntime.editorViewModel"

        XCTAssertTrue(
            normalized.contains(
                "Button(\"Title\"){"
                    + editor
                    + ".setTextStyle(.title)}.keyboardShortcut(\"t\",modifiers:[.command,.shift])"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "Button(\"Heading\"){"
                    + editor
                    + ".setTextStyle(.heading)}.keyboardShortcut(\"h\",modifiers:[.command,.shift])"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "Button(\"Subheading\"){"
                    + editor
                    + ".setTextStyle(.subheading)}.keyboardShortcut(\"j\",modifiers:[.command,.shift])"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "Button(\"Body\"){"
                    + editor
                    + ".setTextStyle(.body)}.keyboardShortcut(\"b\",modifiers:[.command,.shift])"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "Toggle(\"Bold\",isOn:formattingBinding(.bold)).keyboardShortcut(\"b\",modifiers:[.command])"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "Toggle(\"Italic\",isOn:formattingBinding(.italic)).keyboardShortcut(\"i\",modifiers:[.command])"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "Toggle(\"Underline\",isOn:formattingBinding(.underline)).keyboardShortcut(\"u\",modifiers:[.command])"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "Toggle(\"Strikethrough\",isOn:formattingBinding(.strikethrough)).keyboardShortcut(\"x\",modifiers:[.command,.shift])"
            )
        )
    }

    func testMacFormatMenuKeepsNotesFormattingCommandsContextGated() throws {
        let normalized = try normalizedAppCommandsSource()

        XCTAssertTrue(normalized.contains(".disabled(!canApplyTextStyle(.title))"))
        XCTAssertTrue(normalized.contains(".disabled(!canApplyTextStyle(.heading))"))
        XCTAssertTrue(normalized.contains(".disabled(!canApplyTextStyle(.subheading))"))
        XCTAssertTrue(normalized.contains(".disabled(!canApplyTextStyle(.body))"))
        XCTAssertTrue(
            normalized.contains(
                "Toggle(\"Bold\",isOn:formattingBinding(.bold)).keyboardShortcut(\"b\",modifiers:[.command]).disabled(!canFormatNotes)"
            )
        )
        XCTAssertTrue(normalized.contains("Toggle(\"InlineCode\",isOn:formattingBinding(.inlineCode)).disabled(!canFormatNotes)"))
    }

    func testIOSAppSceneRegistersSidebarCommands() throws {
        let normalized = try normalizedSideBarAppSource()

        XCTAssertTrue(
            normalized.contains(
                "WindowGroup{rootContentView}.commands{SidebarCommands(environment:environment)}"
            )
        )
    }

    func testMacSectionCommandsUseDynamicContextualMenu() throws {
        let normalized = try normalizedAppCommandsSource()

        XCTAssertTrue(
            normalized.contains(
                "ifletsectionCommandContext=Self.macSectionCommandContext(" +
                    "focusedSection:environment.focusedSection," +
                    "activeSection:environment.activeSection)"
            )
        )
        XCTAssertFalse(
            normalized.contains(
                "CommandMenu(\"Tasks\"){Button(\"CompleteTask\"){environment.emitShortcutAction(.completeTask)}"
            )
        )
    }

    func testMacCommandsExposeScratchpadShortcut() throws {
        let normalized = try normalizedAppCommandsSource()

        XCTAssertTrue(
            normalized.contains(
                "Button(\"Scratchpad\"){environment.emitShortcutAction(.openScratchpad)}"
                    + ".keyboardShortcut(\"o\",modifiers:[.command,.shift])"
            )
        )
    }

    func testMacCommandsExposeViewMenuForSidebarAndScratchpad() throws {
        let normalized = try normalizedAppCommandsSource()

        XCTAssertFalse(normalized.contains("CommandMenu(\"View\")"))
        XCTAssertTrue(normalized.contains("CommandGroup(before:.toolbar){"))
        XCTAssertTrue(
            normalized.contains(
                "Button(\"ToggleSidebar\"){environment.emitShortcutAction(.toggleSidebar)}"
                    + ".keyboardShortcut(\"s\",modifiers:[.command,.control])"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "Button(\"Scratchpad\"){environment.emitShortcutAction(.openScratchpad)}"
                    + ".keyboardShortcut(\"o\",modifiers:[.command,.shift])"
            )
        )
    }
}

private func normalizedAppCommandsSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try appCommandsSourceForFormattingTests(file: file, line: line)
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}

private func appCommandsSourceForFormattingTests(
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

private func normalizedSideBarAppSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try sideBarAppSource(file: file, line: line)
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
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

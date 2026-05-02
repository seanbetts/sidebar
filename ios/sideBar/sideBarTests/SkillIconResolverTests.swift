import XCTest
@testable import sideBar

final class SkillIconResolverTests: XCTestCase {
    func testIconNameUsesKnownSkillMappings() {
        let skill = SkillItem(
            id: "audio-transcribe",
            name: "Audio",
            description: "Transcribe audio",
            category: "Media",
            tier: .store
        )

        XCTAssertEqual(SkillIconResolver.iconName(for: skill), "waveform")
    }

    func testIconNameFallsBackForUnknownSkill() {
        XCTAssertEqual(
            SkillIconResolver.iconName(skillId: "unknown-skill", iconKey: nil),
            "puzzlepiece.extension"
        )
    }

    func testToolCallIconUsesSkillMetadataWhenPresent() {
        let toolCall = ToolCall(
            id: "tool-1",
            name: "Create Note",
            parameters: [:],
            status: .success,
            skillId: "notes",
            iconKey: "notes"
        )

        XCTAssertEqual(SkillIconResolver.iconName(for: toolCall), "note.text")
    }

    func testToolCallIconFallsBackToToolNameMapping() {
        let legacyToolCall = ToolCall(
            id: "tool-1",
            name: "Create Note",
            parameters: [:],
            status: .success
        )

        XCTAssertEqual(SkillIconResolver.iconName(for: legacyToolCall), "note.text")
    }

    func testEditNoteToolCallFallsBackToNotesIcon() {
        let legacyToolCall = ToolCall(
            id: "tool-2",
            name: "Edit Note",
            parameters: [:],
            status: .success
        )

        XCTAssertEqual(SkillIconResolver.iconName(for: legacyToolCall), "note.text")
    }

    func testConversationsSkillUsesConversationIcon() {
        let skill = SkillItem(
            id: "conversations",
            name: "Conversations",
            description: "Search and rename saved conversations",
            category: "Productivity"
        )

        XCTAssertEqual(SkillIconResolver.iconName(for: skill), "bubble.left.and.bubble.right")
    }

    func testSettingsIconsUseSidebarRailIconsForSectionSkills() {
        let conversations = SkillItem(
            id: "conversations",
            name: "Conversations",
            description: "Search and rename saved conversations",
            category: "Productivity"
        )
        let notes = SkillItem(
            id: "notes",
            name: "Notes",
            description: "Create and edit notes",
            category: "Productivity"
        )
        let files = SkillItem(
            id: "files",
            name: "Files",
            description: "Read and manage files",
            category: "Productivity"
        )
        let websites = SkillItem(
            id: "web-save",
            name: "Websites",
            description: "Save websites to read later",
            category: "Productivity"
        )

        XCTAssertEqual(SkillIconResolver.settingsIconName(for: conversations), AppSection.chat.iconName)
        XCTAssertEqual(SkillIconResolver.settingsIconName(for: notes), AppSection.notes.iconName)
        XCTAssertEqual(SkillIconResolver.settingsIconName(for: files), AppSection.files.iconName)
        XCTAssertEqual(SkillIconResolver.settingsIconName(for: websites), AppSection.websites.iconName)
    }
}

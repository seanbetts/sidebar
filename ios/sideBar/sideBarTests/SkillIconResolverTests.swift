import XCTest
@testable import sideBar
import sideBarShared

final class SkillIconResolverTests: XCTestCase {
    func testAppIconUsesKnownSkillMappings() {
        let skill = SkillItem(
            id: "audio-transcribe",
            name: "Audio",
            description: "Transcribe audio",
            category: "Media",
            tier: .store
        )

        XCTAssertEqual(SkillIconResolver.appIcon(for: skill), AppIcon.Media.waveform)
    }

    func testAppIconFallsBackForUnknownSkill() {
        XCTAssertEqual(
            SkillIconResolver.appIcon(skillId: "unknown-skill", iconKey: nil),
            AppIcon.Skills.fallback
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

        XCTAssertEqual(SkillIconResolver.appIcon(for: toolCall), AppIcon.Content.note)
    }

    func testToolCallIconFallsBackToToolNameMapping() {
        let legacyToolCall = ToolCall(
            id: "tool-1",
            name: "Create Note",
            parameters: [:],
            status: .success
        )

        XCTAssertEqual(SkillIconResolver.appIcon(for: legacyToolCall), AppIcon.Content.note)
    }

    func testEditNoteToolCallFallsBackToNotesIcon() {
        let legacyToolCall = ToolCall(
            id: "tool-2",
            name: "Edit Note",
            parameters: [:],
            status: .success
        )

        XCTAssertEqual(SkillIconResolver.appIcon(for: legacyToolCall), AppIcon.Content.note)
    }

    func testConversationsSkillUsesConversationIcon() {
        let skill = SkillItem(
            id: "conversations",
            name: "Conversations",
            description: "Search and rename saved conversations",
            category: "Productivity"
        )

        XCTAssertEqual(SkillIconResolver.appIcon(for: skill), AppIcon.Skills.conversations)
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

        XCTAssertEqual(SkillIconResolver.settingsAppIcon(for: conversations), AppSection.chat.appIcon)
        XCTAssertEqual(SkillIconResolver.settingsAppIcon(for: notes), AppSection.notes.appIcon)
        XCTAssertEqual(SkillIconResolver.settingsAppIcon(for: files), AppSection.files.appIcon)
        XCTAssertEqual(SkillIconResolver.settingsAppIcon(for: websites), AppSection.websites.appIcon)
    }
}

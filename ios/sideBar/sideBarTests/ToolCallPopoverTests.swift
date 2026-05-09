import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ToolCallPopoverTests: XCTestCase {
    func testToolCallPopoverUsesCompactPopoverPanelType() {
        XCTAssertEqual(toolCallPopoverPanelType(), .compactPopover)
    }

    func testToolCallPopoverDoesNotWrapDetailContentInMacPopoverShell() throws {
        let normalized = try normalizedChatToolComponentsSource()

        XCTAssertFalse(normalized.contains("MacPopoverShell(type:toolCallPopoverPanelType()){"))
        XCTAssertTrue(normalized.contains("ToolCallPopoverContent(toolCalls:toolCalls)"))
    }

    func testChatErrorPopoverUsesCompactPopoverPanelType() {
        XCTAssertEqual(chatErrorPopoverPanelType(), .compactPopover)
    }

    func testSingleToolSummaryUsesHumanReadableSummary() {
        let toolCall = ToolCall(
            id: "tool-1",
            name: "create-note",
            parameters: [:],
            status: .success,
            result: AnyCodable([
                "success": true,
                "summary": "Created note: Shopping List",
                "entities_touched": [
                    [
                        "entity_type": "note",
                        "entity_id": "note-1",
                        "change": "created"
                    ]
                ]
            ])
        )

        let summary = ChatToolPresentation.summary(for: toolCall)

        XCTAssertEqual(summary.primaryText, "Created note: Shopping List")
        XCTAssertEqual(summary.secondaryText, nil)
        XCTAssertFalse(summary.showsToolList)
    }

    func testPromptPreviewDoesNotShowWorkspaceActionInPopover() {
        let sections = ChatToolPresentation.detailSections(for: makePromptPreviewToolCall())

        XCTAssertEqual(
            sections.map(\.kind),
            [.summary]
        )
    }

    func testPromptPreviewToolUsesUserFacingDisplayName() {
        let presentation = ChatToolSummaryPresentation.from(toolCalls: [makePromptPreviewToolCall()])
        let summary = ChatToolPresentation.summary(for: makePromptPreviewToolCall())

        XCTAssertEqual(presentation.text, "System Prompt Preview")
        XCTAssertEqual(summary.primaryText, "System Prompt Preview")
    }

    func testNonNormalizedResultDoesNotExposeTechnicalDetail() {
        let toolCall = ToolCall(
            id: "tool-2",
            name: "lookup-weather",
            parameters: [
                "city": AnyCodable("London")
            ],
            status: .success,
            result: AnyCodable([
                "data": [
                    "temperature": "18C"
                ]
            ])
        )

        let summary = ChatToolPresentation.summary(for: toolCall)
        let sections = ChatToolPresentation.detailSections(for: toolCall)

        XCTAssertEqual(summary.primaryText, "lookup-weather")
        XCTAssertEqual(summary.secondaryText, nil)
        XCTAssertEqual(sections.map(\.kind), [.summary])
    }

    func testMultiToolPopoverUsesListOnlyLayout() {
        let toolCalls = [
            ToolCall(id: "tool-1", name: "Get Note", parameters: [:], status: .success),
            ToolCall(id: "tool-2", name: "Edit Note", parameters: [:], status: .success)
        ]

        XCTAssertTrue(ChatToolPresentation.usesListOnlyPopoverLayout(for: toolCalls))
    }

    private func makePromptPreviewToolCall() -> ToolCall {
        ToolCall(
            id: "prompt-preview",
            name: "Generate Prompts",
            parameters: [
                "assistant_id": AnyCodable("assistant-1")
            ],
            status: .success,
            result: AnyCodable([
                "success": true,
                "summary": "Prepared prompt preview for Sean",
                "data": [
                    "system_prompt": "You are concise.",
                    "system_prompt_sections": [
                        [
                            "id": "system",
                            "title": "System",
                            "source": "system",
                            "chars": 16
                        ]
                    ]
                ]
            ]),
            skillId: "prompt-preview",
            iconKey: "prompt-preview"
        )
    }
}

private func normalizedChatToolComponentsSource(
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
        .appendingPathComponent("Chat")
        .appendingPathComponent("ChatToolComponents.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    } catch {
        XCTFail("Failed to read ChatToolComponents.swift: \(error)", file: file, line: line)
        throw error
    }
}

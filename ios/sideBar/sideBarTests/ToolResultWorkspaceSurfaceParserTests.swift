import XCTest
import sideBarShared
@testable import sideBar

final class ToolResultWorkspaceSurfaceParserTests: XCTestCase {
    func testParseReturnsAgentSurfaceTargetsFromDataWorkspacePatch() {
        let result = AnyCodable([
            "success": true,
            "data": [
                "workspace_patch": [
                    "version": 1,
                    "operations": [
                        [
                            "op": "upsert_agent_surface",
                            "pane": "secondary",
                            "surface": [
                                "type": "chart",
                                "surface_id": "surface-chart-1",
                                "title": "Revenue"
                            ]
                        ]
                    ]
                ]
            ]
        ])

        let targets = ToolResultWorkspaceSurfaceParser.parse(result)

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.pane, .secondary)
        XCTAssertEqual(targets.first?.surface.surfaceId, "surface-chart-1")
        XCTAssertEqual(targets.first?.label, "Show Revenue")
        XCTAssertEqual(targets.first?.iconName, "rectangle.on.rectangle")
    }

    func testParseIgnoresInvalidWorkspacePatchPayloads() {
        let result = AnyCodable([
            "data": [
                "workspace_patch": [
                    "version": "1",
                    "operations": []
                ],
                "workspace_patches": [
                    [
                        "version": 1,
                        "operations": "swap"
                    ]
                ]
            ]
        ])

        let targets = ToolResultWorkspaceSurfaceParser.parse(result)

        XCTAssertTrue(targets.isEmpty)
    }

    func testParseDeduplicatesTargetsByPaneAndSurfaceID() {
        let patch: [String: Any] = [
            "version": 1,
            "operations": [
                [
                    "op": "upsert_agent_surface",
                    "pane": "primary",
                    "surface": [
                        "type": "markdown",
                        "surface_id": "surface-1",
                        "title": "System Prompt"
                    ]
                ]
            ]
        ]

        let result = AnyCodable([
            "workspace_patch": patch,
            "workspace_patches": [patch]
        ])

        let targets = ToolResultWorkspaceSurfaceParser.parse(result)

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.id, "primary:surface-1")
    }

    func testParseToolCallAddsPromptPreviewTarget() {
        let toolCall = ToolCall(
            id: "call-1",
            name: "prompt_preview",
            parameters: [:],
            status: .success,
            result: AnyCodable([
                "system_prompt": "# System Prompt\n\nYou are concise."
            ]),
            skillId: "prompt-preview",
            iconKey: "prompt-preview"
        )

        let targets = ToolResultWorkspaceSurfaceParser.parse(toolCall)

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.id, "primary:prompt-preview")
        XCTAssertEqual(targets.first?.label, "Show System Prompt")
        XCTAssertEqual(targets.first?.iconName, "eye")
    }

    func testParseToolCallAssignsOriginatingSkillIconToWorkspacePatchTargets() {
        let toolCall = ToolCall(
            id: "call-1",
            name: "Generate Prompts",
            parameters: [:],
            status: .success,
            result: AnyCodable([
                "data": [
                    "workspace_patch": [
                        "version": 1,
                        "operations": [
                            [
                                "op": "upsert_agent_surface",
                                "pane": "primary",
                                "surface": [
                                    "type": "markdown",
                                    "surface_id": "surface-1",
                                    "title": "Preview"
                                ]
                            ]
                        ]
                    ]
                ]
            ]),
            skillId: "prompt-preview",
            iconKey: "prompt-preview"
        )

        let targets = ToolResultWorkspaceSurfaceParser.parse(toolCall)

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.iconName, "eye")
    }

    func testParseToolCallsDeduplicatesPromptPreviewTargetsAcrossCalls() {
        let promptResult = AnyCodable([
            "system_prompt": "# System Prompt\n\nYou are concise."
        ])
        let firstCall = ToolCall(
            id: "call-1",
            name: "prompt_preview",
            parameters: [:],
            status: .success,
            result: promptResult
        )
        let secondCall = ToolCall(
            id: "call-2",
            name: "prompt_preview",
            parameters: [:],
            status: .success,
            result: promptResult
        )

        let targets = ToolResultWorkspaceSurfaceParser.parse(toolCalls: [firstCall, secondCall])

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.id, "primary:prompt-preview")
    }
}

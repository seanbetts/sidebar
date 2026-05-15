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
        XCTAssertEqual(targets.first?.appIcon, AppIcon.Workspace.surface)
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
        XCTAssertEqual(targets.first?.label, "Show System Prompt Preview")
        XCTAssertEqual(targets.first?.appIcon, AppIcon.Skills.promptPreview)
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
        XCTAssertEqual(targets.first?.appIcon, AppIcon.Skills.promptPreview)
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

final class ToolResultWorkspaceOpenEntityParserTests: XCTestCase {
    func testParseReturnsOpenEntityTargetFromDataWorkspacePatch() {
        let result = AnyCodable([
            "success": true,
            "data": [
                "workspace_patch": [
                    "version": 1,
                    "operations": [
                        [
                            "op": "open_entity",
                            "entity": [
                                "type": "note",
                                "id": "note-123",
                                "title": "Orion — Project Brief"
                            ],
                            "route_url": "sidebar://notes/note-123",
                            "section": "notes",
                            "pane": "primary"
                        ]
                    ]
                ]
            ]
        ])

        let targets = ToolResultWorkspaceOpenEntityParser.parse(result)

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.id, "primary:note:note-123")
        XCTAssertEqual(targets.first?.label, "Open Orion — Project Brief")
        XCTAssertEqual(targets.first?.appIcon, AppIcon.Content.textDocument)
        XCTAssertEqual(targets.first?.iconName, "doc.text")
        XCTAssertEqual(targets.first?.request.entity.type, "note")
        XCTAssertEqual(targets.first?.request.routeURL?.absoluteString, "sidebar://notes/note-123")
    }

    func testParseToolCallsDeduplicatesOpenEntityTargetsAcrossCalls() {
        let result = AnyCodable([
            "data": [
                "workspace_patch": [
                    "version": 1,
                    "operations": [
                        [
                            "op": "open_entity",
                            "entity": [
                                "type": "website",
                                "id": "site-1",
                                "title": "Research"
                            ],
                            "route_url": "sidebar://websites/site-1",
                            "section": "websites",
                            "pane": "primary"
                        ]
                    ]
                ]
            ]
        ])
        let firstCall = ToolCall(id: "call-1", name: "Open Website", parameters: [:], status: .success, result: result)
        let secondCall = ToolCall(id: "call-2", name: "Open Website", parameters: [:], status: .success, result: result)

        let targets = ToolResultWorkspaceOpenEntityParser.parse(toolCalls: [firstCall, secondCall])

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.id, "primary:website:site-1")
        XCTAssertEqual(targets.first?.label, "Open Research")
        XCTAssertEqual(targets.first?.appIcon, AppIcon.Domain.websites)
        XCTAssertEqual(targets.first?.iconName, "globe")
    }

    func testParseMapsKnownEntityTypesToAppIcons() {
        let cases: [(type: String, expectedIcon: AppIcon, expectedIconName: String)] = [
            ("note", AppIcon.Content.textDocument, "doc.text"),
            ("website", AppIcon.Domain.websites, "globe"),
            ("file", AppIcon.Domain.files, "folder"),
            ("conversation", AppIcon.Domain.chat, "bubble"),
            ("scratchpad", AppIcon.Action.compose, "square.and.pencil"),
            ("task", AppIcon.Domain.tasks, "checkmark.square"),
            ("task_scope", AppIcon.Domain.tasks, "checkmark.square"),
            ("task_project", AppIcon.Domain.tasks, "checkmark.square"),
            ("task_group", AppIcon.Domain.tasks, "checkmark.square"),
            ("unknown_entity", AppIcon.Workspace.openEntityFallback, "arrow.up.forward.app")
        ]

        for testCase in cases {
            let result = AnyCodable([
                "workspace_patch": [
                    "version": 1,
                    "operations": [
                        [
                            "op": "open_entity",
                            "entity": [
                                "type": testCase.type,
                                "id": "\(testCase.type)-1"
                            ],
                            "pane": "primary"
                        ]
                    ]
                ]
            ])

            let target = ToolResultWorkspaceOpenEntityParser.parse(result).first

            XCTAssertEqual(target?.appIcon, testCase.expectedIcon, "Unexpected AppIcon for \(testCase.type)")
            XCTAssertEqual(target?.iconName, testCase.expectedIconName, "Unexpected icon name for \(testCase.type)")
        }
    }
}

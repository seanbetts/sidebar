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
}

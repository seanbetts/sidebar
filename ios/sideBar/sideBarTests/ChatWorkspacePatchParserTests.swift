import XCTest
import sideBarShared
@testable import sideBar

final class ChatWorkspacePatchParserTests: XCTestCase {
    func testParseAcceptsSupportedVersionAndKnownOperations() {
        let result = ChatWorkspacePatchParser.parse(data: AnyCodable([
            "version": 1,
            "operations": [
                ["op": "swap_panes"],
                ["op": "close_pane", "pane": "secondary"]
            ]
        ]))

        guard case .accepted(let actions, let ignoredOperations) = result else {
            return XCTFail("Expected workspace patch to be accepted")
        }
        XCTAssertEqual(ignoredOperations, 0)
        XCTAssertEqual(actions, [.swapPanes, .closePane(.secondary)])
    }

    func testParseIgnoresUnknownOperationsAndUnknownFields() {
        let result = ChatWorkspacePatchParser.parse(data: AnyCodable([
            "version": 1,
            "operations": [
                [
                    "op": "upsert_agent_surface",
                    "pane": "primary",
                    "surface": [
                        "type": "chart",
                        "surface_id": "surface-chart-1",
                        "title": "Revenue",
                        "payload": ["summary": "Q1"],
                        "context_menu_actions": ["copy_markdown", "share_text", "download"],
                        "future_field": "ignored"
                    ],
                    "unknown_field": 123
                ],
                ["op": "future_operation", "pane": "primary"]
            ],
            "metadata": ["request_id": "abc123"]
        ]))

        guard case .accepted(let actions, let ignoredOperations) = result else {
            return XCTFail("Expected workspace patch to be accepted")
        }
        XCTAssertEqual(ignoredOperations, 1)
        XCTAssertEqual(actions.count, 1)
        guard case .presentAgentSurface(let surface, let pane) = actions[0] else {
            return XCTFail("Expected upsert operation to map to presentAgentSurface")
        }
        XCTAssertEqual(pane, .primary)
        XCTAssertEqual(surface.type, "chart")
        XCTAssertEqual(surface.surfaceId, "surface-chart-1")
        XCTAssertEqual(surface.payload["summary"], "Q1")
        XCTAssertEqual(
            surface.contextMenuActions,
            [.copyMarkdown, .shareText, .download]
        )
    }

    func testParseOpenEntityWorkspacePatchWithNativeRoute() {
        let result = ChatWorkspacePatchParser.parse(data: AnyCodable([
            "version": 1,
            "operations": [[
                "op": "open_entity",
                "entity": [
                    "type": "note",
                    "id": "note-123",
                    "title": "Orion — Project Brief"
                ],
                "route_url": "sidebar://notes/note-123",
                "section": "notes",
                "pane": "primary"
            ]]
        ]))

        guard case .accepted(let actions, let ignoredOperations) = result else {
            return XCTFail("Expected workspace patch to be accepted")
        }
        XCTAssertEqual(ignoredOperations, 0)
        XCTAssertEqual(actions.count, 1)
        guard case .openEntity(let request) = actions[0] else {
            return XCTFail("Expected open entity action")
        }
        XCTAssertEqual(request.entity.type, "note")
        XCTAssertEqual(request.entity.id, "note-123")
        XCTAssertEqual(request.entity.title, "Orion — Project Brief")
        XCTAssertEqual(request.routeURL?.absoluteString, "sidebar://notes/note-123")
        XCTAssertEqual(request.section, .notes)
        XCTAssertEqual(request.pane, .primary)
    }

    func testParseRejectsUnsupportedVersion() {
        let result = ChatWorkspacePatchParser.parse(data: AnyCodable([
            "version": 3,
            "operations": [["op": "swap_panes"]]
        ]))

        guard case .rejected(let reason) = result else {
            return XCTFail("Expected workspace patch to be rejected")
        }
        XCTAssertTrue(reason.contains("Unsupported workspace patch version"))
    }

    func testParseRejectsMissingOperations() {
        let result = ChatWorkspacePatchParser.parse(data: AnyCodable([
            "version": 1
        ]))

        guard case .rejected(let reason) = result else {
            return XCTFail("Expected workspace patch to be rejected")
        }
        XCTAssertTrue(reason.contains("missing operations"))
    }
}

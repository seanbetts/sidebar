import XCTest
@testable import sideBar
import sideBarShared

final class WorkspaceModelsAgentSurfaceTests: XCTestCase {
    func testSurfaceMetadataDefaultsToDisplayReadOnly() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: .markdown,
            surfaceId: "surface-md-1"
        )

        XCTAssertEqual(descriptor.surfaceClass, .display)
        XCTAssertEqual(descriptor.authorityMode, .readOnly)
        XCTAssertNil(descriptor.boundEntity)
        XCTAssertEqual(descriptor.collaborationScope, .none)
    }

    func testSurfaceMetadataParsesBoundCollaborativeSurface() {
        let result = ChatWorkspacePatchParser.parse(
            data: AnyCodable([
                "version": 1,
                "operations": [[
                    "op": "present_agent_surface",
                    "pane": "primary",
                    "surface": [
                        "type": "form",
                        "surface_id": "surface-note-1",
                        "surface_class": "bound_entity",
                        "authority_mode": "collaborative",
                        "bound_entity": [
                            "type": "note",
                            "id": "note-123"
                        ],
                        "collaboration_scope": [
                            "mode": "conversation_bound_entity",
                            "entity_type": "note",
                            "entity_id": "note-123"
                        ]
                    ]
                ]]
            ])
        )

        guard case .accepted(let actions, _) = result,
              case .presentAgentSurface(let surface, _) = actions.first else {
            return XCTFail("Expected parsed surface action")
        }

        XCTAssertEqual(surface.surfaceClass, .boundEntity)
        XCTAssertEqual(surface.authorityMode, .collaborative)
        XCTAssertEqual(surface.boundEntity?.entityType, "note")
        XCTAssertEqual(surface.boundEntity?.entityId, "note-123")
        XCTAssertEqual(
            surface.collaborationScope,
            .conversationBoundEntity(entityType: "note", entityId: "note-123")
        )
    }

    func testSurfaceTypeMapsKnownRawValue() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: "map",
            surfaceId: "surface-map-1"
        )

        XCTAssertEqual(descriptor.surfaceType, .map)
    }

    func testSurfaceTypeFallsBackToActionPanelForUnknownRawValue() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: "custom-widget",
            surfaceId: "surface-custom-1"
        )

        XCTAssertEqual(descriptor.surfaceType, .actionPanel)
    }

    func testCapabilitiesDefaultAllEnabled() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: .markdown,
            surfaceId: "surface-md-1"
        )

        XCTAssertTrue(descriptor.capabilities.canRefresh)
        XCTAssertTrue(descriptor.capabilities.canClose)
        XCTAssertTrue(descriptor.capabilities.canPin)
        XCTAssertTrue(descriptor.capabilities.canInspectData)
    }
}

import XCTest
@testable import sideBar
import sideBarShared

@MainActor
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

    func testChartPointsParseStructuredPointsPayload() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: .chart,
            surfaceId: "surface-chart-1",
            payload: [
                "points": """
                [
                  {"label":"Mon","value":12},
                  {"label":"Tue","value":18.5}
                ]
                """
            ]
        )

        XCTAssertEqual(
            descriptor.chartPoints,
            [
                AgentWorkspaceChartPoint(label: "Mon", value: 12),
                AgentWorkspaceChartPoint(label: "Tue", value: 18.5)
            ]
        )
    }

    func testChartPointsParseParallelAxisArrays() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: .chart,
            surfaceId: "surface-chart-2",
            payload: [
                "x_values": #"["Jan","Feb","Mar"]"#,
                "y_values": "[3,5,8]"
            ]
        )

        XCTAssertEqual(
            descriptor.chartPoints,
            [
                AgentWorkspaceChartPoint(label: "Jan", value: 3),
                AgentWorkspaceChartPoint(label: "Feb", value: 5),
                AgentWorkspaceChartPoint(label: "Mar", value: 8)
            ]
        )
    }

    func testMapLocationParsesCoordinatePayload() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: .map,
            surfaceId: "surface-map-1",
            payload: [
                "latitude": "51.5074",
                "longitude": "-0.1278",
                "label": "London"
            ]
        )

        XCTAssertEqual(
            descriptor.mapLocation,
            AgentWorkspaceMapLocation(id: "surface-map-1", latitude: 51.5074, longitude: -0.1278, label: "London")
        )
    }

    func testFormFieldsParseStructuredPayload() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-form-1",
            payload: [
                "fields": """
                [
                  {
                    "id": "title",
                    "label": "Title",
                    "value": "Task 11",
                    "placeholder": "Add a title"
                  }
                ]
                """
            ]
        )

        XCTAssertEqual(
            descriptor.formFields,
            [
                AgentWorkspaceFormField(
                    id: "title",
                    label: "Title",
                    value: "Task 11",
                    placeholder: "Add a title"
                )
            ]
        )
    }

    func testActionItemsFallbackToPrimaryAndSecondaryPayload() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: .actionPanel,
            surfaceId: "surface-actions-1",
            payload: [
                "primary_action": "Open note",
                "secondary_action": "Dismiss"
            ]
        )

        XCTAssertEqual(
            descriptor.actionItems,
            [
                AgentWorkspaceActionItem(id: "primary_action", title: "Open note", style: .primary),
                AgentWorkspaceActionItem(id: "secondary_action", title: "Dismiss", style: .secondary)
            ]
        )
    }

    func testStructuredActionItemsConvertExternalSystemImagesToAppIcons() {
        let descriptor = AgentWorkspaceSurfaceDescriptor(
            type: .actionPanel,
            surfaceId: "surface-actions-2",
            payload: [
                "actions": """
                [
                  {
                    "id": "open_note",
                    "title": "Open note",
                    "system_image": "doc.text",
                    "style": "primary"
                  },
                  {
                    "label": "Dismiss",
                    "systemImage": "xmark",
                    "variant": "secondary"
                  }
                ]
                """
            ]
        )

        XCTAssertEqual(
            descriptor.actionItems,
            [
                AgentWorkspaceActionItem(
                    id: "open_note",
                    title: "Open note",
                    appIcon: AppIcon.Content.textDocument,
                    style: .primary
                ),
                AgentWorkspaceActionItem(
                    id: "dismiss",
                    title: "Dismiss",
                    appIcon: AppIcon.Action.close,
                    style: .secondary
                )
            ]
        )
    }

    func testOnlyInteractiveBlockSurfacesAllowEphemeralInteractionInV1() {
        let display = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-display-1"
        )
        let collaborativeBoundEntity = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-bound-1",
            surfaceClass: .boundEntity,
            authorityMode: .collaborative
        )
        let interactiveBlock = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-block-1",
            surfaceClass: .interactiveBlock,
            authorityMode: .userEditable
        )

        XCTAssertFalse(display.supportsEphemeralInteraction)
        XCTAssertFalse(collaborativeBoundEntity.supportsEphemeralInteraction)
        XCTAssertTrue(interactiveBlock.supportsEphemeralInteraction)
    }
}

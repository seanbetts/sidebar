import XCTest
@testable import sideBar

@MainActor
final class WorkspaceStoreCollaborativeSurfaceTests: XCTestCase {
    func testReducerPresentAgentSurfaceMergesCollaborativeBoundEntityUpdates() {
        let current = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-note-1",
            payload: ["field_one": "Local draft"],
            surfaceClass: .boundEntity,
            authorityMode: .collaborative,
            boundEntity: .init(entityType: "note", entityId: "note-123"),
            collaborationScope: .conversationBoundEntity(
                entityType: "note",
                entityId: "note-123"
            ),
            capabilities: AgentWorkspaceSurfaceCapabilities(
                canRefresh: false,
                canClose: true,
                canPin: true,
                canInspectData: false
            ),
            isPinned: true
        )
        let incoming = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-note-1",
            title: "Shared note",
            payload: ["field_one": "Assistant update"],
            surfaceClass: .boundEntity,
            authorityMode: .collaborative,
            boundEntity: .init(entityType: "note", entityId: "note-123"),
            collaborationScope: .conversationBoundEntity(
                entityType: "note",
                entityId: "note-123"
            ),
            capabilities: AgentWorkspaceSurfaceCapabilities(
                canRefresh: true,
                canClose: true,
                canPin: false,
                canInspectData: true
            ),
            isPinned: false
        )
        let state = WorkspaceState(
            mode: .agent,
            layout: .split,
            primaryPane: WorkspacePaneState(
                pane: .primary,
                descriptor: .agentSurface(current)
            )
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .presentAgentSurface(incoming, pane: .primary)
        )

        guard case .agentSurface(let surface) = next.primaryPane.descriptor else {
            return XCTFail("Expected collaborative agent surface")
        }

        XCTAssertEqual(surface.surfaceId, current.surfaceId)
        XCTAssertEqual(surface.boundEntity?.entityId, "note-123")
        XCTAssertEqual(surface.authorityMode, .collaborative)
        XCTAssertEqual(surface.title, "Shared note")
        XCTAssertEqual(surface.payload["field_one"], "Assistant update")
        XCTAssertTrue(surface.capabilities.canRefresh)
        XCTAssertFalse(surface.capabilities.canPin)
        XCTAssertTrue(surface.capabilities.canInspectData)
        XCTAssertTrue(surface.isPinned)
    }

    func testReducerPresentAgentSurfaceReplacesCollaborativeSurfaceWhenSurfaceIDChanges() {
        let current = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-note-form",
            payload: ["field_one": "Local draft"],
            surfaceClass: .boundEntity,
            authorityMode: .collaborative,
            boundEntity: .init(entityType: "note", entityId: "note-123"),
            collaborationScope: .conversationBoundEntity(
                entityType: "note",
                entityId: "note-123"
            ),
            capabilities: AgentWorkspaceSurfaceCapabilities(
                canRefresh: false,
                canClose: true,
                canPin: true,
                canInspectData: false
            ),
            isPinned: true
        )
        let incoming = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-note-summary",
            title: "Shared note summary",
            payload: ["field_one": "Assistant update"],
            surfaceClass: .boundEntity,
            authorityMode: .collaborative,
            boundEntity: .init(entityType: "note", entityId: "note-123"),
            collaborationScope: .conversationBoundEntity(
                entityType: "note",
                entityId: "note-123"
            ),
            capabilities: AgentWorkspaceSurfaceCapabilities(
                canRefresh: true,
                canClose: true,
                canPin: false,
                canInspectData: true
            )
        )
        let state = WorkspaceState(
            mode: .agent,
            layout: .split,
            primaryPane: WorkspacePaneState(
                pane: .primary,
                descriptor: .agentSurface(current)
            )
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .presentAgentSurface(incoming, pane: .primary)
        )

        XCTAssertEqual(next.primaryPane.descriptor, .agentSurface(incoming))
    }

    func testReducerPresentAgentSurfaceReplacesCollaborativeSurfaceWhenTypeChanges() {
        let current = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-note-1",
            payload: ["field_one": "Local draft"],
            surfaceClass: .boundEntity,
            authorityMode: .collaborative,
            boundEntity: .init(entityType: "note", entityId: "note-123"),
            collaborationScope: .conversationBoundEntity(
                entityType: "note",
                entityId: "note-123"
            ),
            capabilities: AgentWorkspaceSurfaceCapabilities(
                canRefresh: false,
                canClose: true,
                canPin: true,
                canInspectData: false
            ),
            isPinned: true
        )
        let incoming = AgentWorkspaceSurfaceDescriptor(
            type: .markdown,
            surfaceId: "surface-note-1",
            title: "Shared note summary",
            payload: ["markdown": "Assistant summary"],
            surfaceClass: .boundEntity,
            authorityMode: .collaborative,
            boundEntity: .init(entityType: "note", entityId: "note-123"),
            collaborationScope: .conversationBoundEntity(
                entityType: "note",
                entityId: "note-123"
            ),
            capabilities: AgentWorkspaceSurfaceCapabilities(
                canRefresh: true,
                canClose: true,
                canPin: false,
                canInspectData: true
            )
        )
        let state = WorkspaceState(
            mode: .agent,
            layout: .split,
            primaryPane: WorkspacePaneState(
                pane: .primary,
                descriptor: .agentSurface(current)
            )
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .presentAgentSurface(incoming, pane: .primary)
        )

        XCTAssertEqual(next.primaryPane.descriptor, .agentSurface(incoming))
    }
}

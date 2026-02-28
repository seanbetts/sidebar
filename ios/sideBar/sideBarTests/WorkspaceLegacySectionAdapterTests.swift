import XCTest
@testable import sideBar

final class WorkspaceLegacySectionAdapterTests: XCTestCase {
    func testDescriptorMappingForBuiltInSection() {
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.descriptor(for: .notes),
            .builtIn(.notes)
        )
    }

    func testSectionMappingIgnoresEmptyAndAgentSurfaceDescriptors() {
        XCTAssertNil(WorkspaceLegacySectionAdapter.section(from: .empty))
        XCTAssertNil(
            WorkspaceLegacySectionAdapter.section(
                from: .agentSurface(
                    AgentWorkspaceSurfaceDescriptor(type: "map", surfaceId: "surface-1")
                )
            )
        )
    }

    func testProjectionUsesWorkspaceDescriptorsWhenAvailable() {
        let state = WorkspaceState(
            layout: .split,
            primaryPane: WorkspacePaneState(
                pane: .primary,
                descriptor: .builtIn(.tasks)
            ),
            secondaryPane: WorkspacePaneState(
                pane: .secondary,
                descriptor: .builtIn(.chat)
            )
        )

        let projection = WorkspaceLegacySectionAdapter.makeProjection(
            workspaceState: state,
            fallbackPrimarySection: .notes,
            fallbackSecondarySection: .files,
            fallbackCompactSelection: .websites
        )

        XCTAssertEqual(projection.primaryDescriptor, .builtIn(.tasks))
        XCTAssertEqual(projection.secondaryDescriptor, .builtIn(.chat))
        XCTAssertEqual(projection.compactSelection, .tasks)
    }

    func testProjectionFallsBackWhenWorkspaceDescriptorsAreEmpty() {
        let state = WorkspaceState(
            layout: .split,
            primaryPane: WorkspacePaneState(
                pane: .primary,
                descriptor: .empty
            ),
            secondaryPane: WorkspacePaneState(
                pane: .secondary,
                descriptor: .empty
            )
        )

        let projection = WorkspaceLegacySectionAdapter.makeProjection(
            workspaceState: state,
            fallbackPrimarySection: .websites,
            fallbackSecondarySection: .chat,
            fallbackCompactSelection: .files
        )

        XCTAssertEqual(projection.primaryDescriptor, .builtIn(.websites))
        XCTAssertEqual(projection.secondaryDescriptor, .builtIn(.chat))
        XCTAssertEqual(projection.compactSelection, .files)
    }

    func testProjectionCompactsSecondaryAndUsesFallbackForSelection() {
        let state = WorkspaceState(
            layout: .compact,
            primaryPane: WorkspacePaneState(
                pane: .primary,
                descriptor: .empty
            ),
            secondaryPane: nil
        )

        let projection = WorkspaceLegacySectionAdapter.makeProjection(
            workspaceState: state,
            fallbackPrimarySection: .notes,
            fallbackSecondarySection: .chat,
            fallbackCompactSelection: nil
        )

        XCTAssertEqual(projection.primaryDescriptor, .builtIn(.notes))
        XCTAssertEqual(projection.secondaryDescriptor, .empty)
        XCTAssertEqual(projection.compactSelection, .notes)
    }
}

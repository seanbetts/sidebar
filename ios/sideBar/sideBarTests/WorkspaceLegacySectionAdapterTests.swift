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

    func testCompactDetailDescriptorUsesPrimaryDescriptorForCompactSelection() {
        let projection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .agentSurface(
                AgentWorkspaceSurfaceDescriptor(type: "map", surfaceId: "surface-1")
            ),
            secondaryDescriptor: .empty,
            compactSelection: .websites
        )

        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.compactDetailDescriptor(
                for: .websites,
                projection: projection
            ),
            projection.primaryDescriptor
        )
    }

    func testCompactDetailDescriptorFallsBackToBuiltInForOtherTabs() {
        let projection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .agentSurface(
                AgentWorkspaceSurfaceDescriptor(type: "chart", surfaceId: "surface-2")
            ),
            secondaryDescriptor: .empty,
            compactSelection: .websites
        )

        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.compactDetailDescriptor(
                for: .notes,
                projection: projection
            ),
            .builtIn(.notes)
        )
    }

    func testIsSectionVisibleUsesCompactSelectionWhenCompact() {
        let projection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .agentSurface(
                AgentWorkspaceSurfaceDescriptor(type: "table", surfaceId: "surface-3")
            ),
            secondaryDescriptor: .empty,
            compactSelection: .files
        )

        XCTAssertTrue(
            WorkspaceLegacySectionAdapter.isSectionVisible(
                .files,
                projection: projection,
                isCompactLayout: true
            )
        )
        XCTAssertFalse(
            WorkspaceLegacySectionAdapter.isSectionVisible(
                .notes,
                projection: projection,
                isCompactLayout: true
            )
        )
    }

    func testIsSectionVisibleChecksBuiltInDescriptorsWhenSplit() {
        let projection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .builtIn(.notes),
            secondaryDescriptor: .builtIn(.files),
            compactSelection: .chat
        )

        XCTAssertTrue(
            WorkspaceLegacySectionAdapter.isSectionVisible(
                .notes,
                projection: projection,
                isCompactLayout: false
            )
        )
        XCTAssertTrue(
            WorkspaceLegacySectionAdapter.isSectionVisible(
                .files,
                projection: projection,
                isCompactLayout: false
            )
        )
        XCTAssertFalse(
            WorkspaceLegacySectionAdapter.isSectionVisible(
                .tasks,
                projection: projection,
                isCompactLayout: false
            )
        )
    }

    func testResolvedActiveSectionReturnsCompactSelectionWhenCompact() {
        let projection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .builtIn(.notes),
            secondaryDescriptor: .builtIn(.files),
            compactSelection: .tasks
        )

        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.resolvedActiveSection(
                projection: projection,
                isCompactLayout: true,
                isSettingsPresented: false,
                fallbackSidebarSelection: .chat
            ),
            .tasks
        )
    }

    func testResolvedActiveSectionPrioritizesSettingsAndPrimaryThenFallbacks() {
        let settingsProjection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .builtIn(.notes),
            secondaryDescriptor: .builtIn(.files),
            compactSelection: .chat
        )
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.resolvedActiveSection(
                projection: settingsProjection,
                isCompactLayout: false,
                isSettingsPresented: true,
                fallbackSidebarSelection: .chat
            ),
            .settings
        )

        let primaryProjection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .builtIn(.websites),
            secondaryDescriptor: .builtIn(.files),
            compactSelection: .chat
        )
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.resolvedActiveSection(
                projection: primaryProjection,
                isCompactLayout: false,
                isSettingsPresented: false,
                fallbackSidebarSelection: .chat
            ),
            .websites
        )

        let fallbackProjection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .agentSurface(
                AgentWorkspaceSurfaceDescriptor(type: "map", surfaceId: "surface-4")
            ),
            secondaryDescriptor: .builtIn(.tasks),
            compactSelection: .chat
        )
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.resolvedActiveSection(
                projection: fallbackProjection,
                isCompactLayout: false,
                isSettingsPresented: false,
                fallbackSidebarSelection: .notes
            ),
            .notes
        )
    }

    func testPrimaryWorkspaceSectionForRotationUsesProjectionAndFallback() {
        let compactProjection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .builtIn(.notes),
            secondaryDescriptor: .empty,
            compactSelection: .chat
        )
        XCTAssertNil(
            WorkspaceLegacySectionAdapter.primaryWorkspaceSectionForRotation(
                projection: compactProjection,
                isCompactLayout: true,
                fallbackSidebarSelection: .files
            )
        )

        let splitProjection = WorkspaceLegacySectionProjection(
            primaryDescriptor: .agentSurface(
                AgentWorkspaceSurfaceDescriptor(type: "chart", surfaceId: "surface-5")
            ),
            secondaryDescriptor: .builtIn(.chat),
            compactSelection: .chat
        )
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.primaryWorkspaceSectionForRotation(
                projection: splitProjection,
                isCompactLayout: false,
                fallbackSidebarSelection: .websites
            ),
            .websites
        )
    }

    func testSyncDirectiveSetsBuiltInAndEmptyDescriptors() {
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.syncDirective(for: .builtIn(.files)),
            .set(.files)
        )
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.syncDirective(for: .empty),
            .set(nil)
        )
    }

    func testSyncDirectiveIgnoresAgentSurfaceDescriptors() {
        XCTAssertEqual(
            WorkspaceLegacySectionAdapter.syncDirective(
                for: .agentSurface(
                    AgentWorkspaceSurfaceDescriptor(type: "map", surfaceId: "surface-6")
                )
            ),
            .keepCurrent
        )
    }
}

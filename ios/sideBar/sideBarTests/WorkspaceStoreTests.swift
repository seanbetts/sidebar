import Combine
import XCTest
@testable import sideBar

// swiftlint:disable type_body_length
@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private static var retainedStores: [WorkspaceStore] = []

    func testSyncLegacySnapshotMapsSplitLayoutDescriptors() {
        let store = makeStore()
        let snapshot = makeSnapshot(
            isCompactLayout: false,
            sidebarSelection: .notes,
            primarySection: .notes,
            secondarySection: .chat,
            phoneSelection: nil,
            activeSection: .notes,
            focusedSection: .notes
        )

        store.syncLegacySnapshot(snapshot, source: "unit_test")

        XCTAssertEqual(store.state.layout, .split)
        XCTAssertEqual(store.state.primaryPane.descriptor, .builtIn(.notes))
        XCTAssertEqual(store.state.secondaryPane?.descriptor, .builtIn(.chat))
        XCTAssertEqual(store.state.sidebarSelection, .notes)
        XCTAssertEqual(store.state.activeSection, .notes)
        XCTAssertEqual(store.state.focusedSection, .notes)
        XCTAssertEqual(store.parityDivergenceCount, 0)
        XCTAssertNil(store.lastParityDivergence)
    }

    func testSyncLegacySnapshotMapsCompactLayoutToSinglePane() {
        let store = makeStore()
        let snapshot = makeSnapshot(
            isCompactLayout: true,
            sidebarSelection: .tasks,
            primarySection: nil,
            secondarySection: .chat,
            phoneSelection: .tasks,
            activeSection: .tasks,
            focusedSection: .tasks
        )

        store.syncLegacySnapshot(snapshot, source: "unit_test")

        XCTAssertEqual(store.state.layout, .compact)
        XCTAssertEqual(store.state.primaryPane.descriptor, .builtIn(.tasks))
        XCTAssertNil(store.state.secondaryPane)
        XCTAssertEqual(store.parityDivergenceCount, 0)
        XCTAssertNil(store.lastParityDivergence)
    }

    func testSyncLegacySnapshotUsesSidebarFallbackForCompactPrimaryContent() {
        let store = makeStore()
        let snapshot = makeSnapshot(
            isCompactLayout: true,
            sidebarSelection: .files,
            primarySection: nil,
            secondarySection: .chat,
            phoneSelection: nil,
            activeSection: .notes,
            focusedSection: .notes
        )

        store.syncLegacySnapshot(snapshot, source: "unit_test")

        XCTAssertEqual(store.state.primaryPane.descriptor, .builtIn(.files))
    }

    func testDispatchAfterLegacySyncReportsDivergenceWhenStateDrifts() {
        let store = makeStore()
        let snapshot = makeSnapshot(
            isCompactLayout: false,
            sidebarSelection: .notes,
            primarySection: .notes,
            secondarySection: .tasks,
            phoneSelection: nil,
            activeSection: .notes,
            focusedSection: .notes
        )

        store.syncLegacySnapshot(snapshot, source: "unit_test")
        store.dispatch(.swapPanes, source: "unit_test_swap")

        XCTAssertEqual(store.parityDivergenceCount, 1)
        XCTAssertNotNil(store.lastParityDivergence)
    }

    func testReducerSwapPanesPromotesSecondaryAndUpdatesLastNonChatSection() {
        let state = WorkspaceState(
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.notes)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.tasks)),
            sidebarSelection: .notes,
            activeSection: .notes,
            focusedSection: .notes,
            lastNonChatSection: .notes
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .swapPanes
        )

        XCTAssertEqual(next.primaryPane.descriptor, .builtIn(.tasks))
        XCTAssertEqual(next.secondaryPane?.descriptor, .builtIn(.notes))
        XCTAssertEqual(next.lastNonChatSection, .tasks)
    }

    func testReducerSwapPanesPreservesLastNonChatWhenPrimaryBecomesChat() {
        let state = WorkspaceState(
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.websites)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.chat)),
            sidebarSelection: .websites,
            activeSection: .websites,
            focusedSection: .websites,
            lastNonChatSection: .websites
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .swapPanes
        )

        XCTAssertEqual(next.primaryPane.descriptor, .builtIn(.chat))
        XCTAssertEqual(next.secondaryPane?.descriptor, .builtIn(.websites))
        XCTAssertEqual(next.lastNonChatSection, .websites)
    }

    func testDispatchReportsParityDivergenceAfterLegacySyncWhenStateDrifts() {
        let store = makeStore()
        let snapshot = makeSnapshot(
            isCompactLayout: false,
            sidebarSelection: .chat,
            primarySection: nil,
            secondarySection: .chat,
            phoneSelection: nil,
            activeSection: .chat,
            focusedSection: .chat
        )
        store.syncLegacySnapshot(snapshot, source: "unit_test")

        store.dispatch(
            .selectSection(.notes),
            source: "unit_test_select"
        )

        XCTAssertEqual(store.parityDivergenceCount, 1)
        XCTAssertNotNil(store.lastParityDivergence)
    }

    func testDispatchDoesNotPublishWhenReducerReturnsUnchangedState() {
        let store = makeStore()
        let expectation = expectation(description: "workspace state should not republish")
        expectation.isInverted = true
        var cancellables = Set<AnyCancellable>()

        store.$state
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        store.dispatch(.setLeftPanelExpanded(true), source: "unit_test_noop")

        wait(for: [expectation], timeout: 0.1)
        XCTAssertEqual(store.state.isLeftPanelExpanded, true)
    }

    func testReducerSelectSectionUpdatesCompactPrimaryDescriptor() {
        let state = WorkspaceState(
            layout: .compact,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.chat)),
            secondaryPane: nil,
            sidebarSelection: .chat,
            activeSection: .chat,
            focusedSection: .chat
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .selectSection(.files)
        )

        XCTAssertEqual(next.primaryPane.descriptor, .builtIn(.files))
        XCTAssertNil(next.secondaryPane)
        XCTAssertEqual(next.sidebarSelection, .files)
        XCTAssertEqual(next.activeSection, .files)
        XCTAssertEqual(next.focusedSection, .files)
    }

    func testReducerSelectSectionPromotesSecondaryWhenPrimaryChatInSplitLayout() {
        let state = WorkspaceState(
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.chat)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.tasks)),
            sidebarSelection: .chat,
            activeSection: .chat,
            focusedSection: .chat
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .selectSection(.websites)
        )

        XCTAssertEqual(next.primaryPane.descriptor, .builtIn(.chat))
        XCTAssertEqual(next.secondaryPane?.descriptor, .builtIn(.websites))
        XCTAssertEqual(next.lastNonChatSection, .websites)
        XCTAssertEqual(next.sidebarSelection, .websites)
    }

    func testReducerSelectSectionRoutesChatToSecondaryInSplitLayout() {
        let state = WorkspaceState(
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.notes)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.chat)),
            sidebarSelection: .notes,
            activeSection: .notes,
            focusedSection: .notes
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .selectSection(.chat)
        )

        XCTAssertEqual(next.primaryPane.descriptor, .empty)
        XCTAssertEqual(next.secondaryPane?.descriptor, .builtIn(.chat))
        XCTAssertEqual(next.sidebarSelection, .chat)
        XCTAssertEqual(next.activeSection, .chat)
        XCTAssertEqual(next.focusedSection, .chat)
    }

    func testReducerPresentAgentSurfaceSetsAgentModeAndPrimaryDescriptor() {
        let state = WorkspaceState(
            mode: .core,
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.notes)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.chat))
        )
        let surface = AgentWorkspaceSurfaceDescriptor(
            type: .chart,
            surfaceId: "surface-chart-1",
            title: "Revenue"
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .presentAgentSurface(surface, pane: .primary)
        )

        XCTAssertEqual(next.mode, .agent)
        XCTAssertEqual(next.primaryPane.descriptor, .agentSurface(surface))
    }

    func testReducerPresentAgentSurfaceReplacesDisplaySurfaceInPlace() {
        let original = AgentWorkspaceSurfaceDescriptor(
            type: .markdown,
            surfaceId: "surface-1",
            payload: ["markdown": "Old"]
        )
        let replacement = AgentWorkspaceSurfaceDescriptor(
            type: .markdown,
            surfaceId: "surface-1",
            payload: ["markdown": "New"]
        )
        let state = WorkspaceState(
            mode: .agent,
            layout: .split,
            primaryPane: WorkspacePaneState(
                pane: .primary,
                descriptor: .agentSurface(original)
            )
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .presentAgentSurface(replacement, pane: .primary)
        )

        XCTAssertEqual(next.primaryPane.descriptor, .agentSurface(replacement))
    }

    func testReducerPresentAgentSurfacePreservesCollaborativeBoundEntityDescriptorIdentity() {
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
            )
        )
        let incoming = AgentWorkspaceSurfaceDescriptor(
            type: .form,
            surfaceId: "surface-note-1",
            payload: ["field_one": "Assistant update"],
            surfaceClass: .boundEntity,
            authorityMode: .collaborative,
            boundEntity: .init(entityType: "note", entityId: "note-123"),
            collaborationScope: .conversationBoundEntity(
                entityType: "note",
                entityId: "note-123"
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

        guard case .agentSurface(let surface) = next.primaryPane.descriptor else {
            return XCTFail("Expected collaborative agent surface")
        }

        XCTAssertEqual(surface.surfaceId, current.surfaceId)
        XCTAssertEqual(surface.boundEntity?.entityId, "note-123")
        XCTAssertEqual(surface.authorityMode, .collaborative)
        XCTAssertEqual(surface.payload["field_one"], "Local draft")
    }

    func testReducerSetAgentSurfacePinnedUpdatesMatchingSurface() {
        let surface = AgentWorkspaceSurfaceDescriptor(
            type: .table,
            surfaceId: "surface-table-1",
            title: "Rows"
        )
        let state = WorkspaceState(
            mode: .agent,
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .agentSurface(surface)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.chat))
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .setAgentSurfacePinned(surfaceId: "surface-table-1", isPinned: true)
        )

        guard case .agentSurface(let updatedSurface) = next.primaryPane.descriptor else {
            return XCTFail("Expected primary pane to remain an agent surface")
        }
        XCTAssertTrue(updatedSurface.isPinned)
        XCTAssertEqual(next.mode, .agent)
    }

    func testReducerClosePaneReturnsModeToCoreWhenNoAgentSurfacesRemain() {
        let primarySurface = AgentWorkspaceSurfaceDescriptor(
            type: .map,
            surfaceId: "surface-map-1",
            title: "Map"
        )
        let state = WorkspaceState(
            mode: .agent,
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .agentSurface(primarySurface)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .empty)
        )

        let next = WorkspaceReducer.reduce(
            state: state,
            action: .closePane(.primary)
        )

        XCTAssertEqual(next.primaryPane.descriptor, .empty)
        XCTAssertEqual(next.mode, .core)
    }

    func testReducerChromeActionsUpdateWorkspacePresentationState() {
        var state = WorkspaceState(
            mode: .core,
            layout: .split,
            primaryPane: WorkspacePaneState(pane: .primary, descriptor: .builtIn(.chat)),
            secondaryPane: WorkspacePaneState(pane: .secondary, descriptor: .builtIn(.notes)),
            isLeftPanelExpanded: true,
            isWorkspaceExpanded: false,
            isWorkspaceExpandedByRotation: false,
            isSettingsPresented: false
        )

        state = WorkspaceReducer.reduce(
            state: state,
            action: .setLeftPanelExpanded(false)
        )
        state = WorkspaceReducer.reduce(
            state: state,
            action: .setWorkspaceExpanded(true)
        )
        state = WorkspaceReducer.reduce(
            state: state,
            action: .setWorkspaceExpandedByRotation(true)
        )
        state = WorkspaceReducer.reduce(
            state: state,
            action: .setSettingsPresented(true)
        )

        XCTAssertFalse(state.isLeftPanelExpanded)
        XCTAssertTrue(state.isWorkspaceExpanded)
        XCTAssertTrue(state.isWorkspaceExpandedByRotation)
        XCTAssertTrue(state.isSettingsPresented)
    }

    func testSyncLegacySnapshotDoesNotReplaceAgentDescriptorsWhenModeIsAgent() {
        let store = makeStore()
        let surface = AgentWorkspaceSurfaceDescriptor(
            type: .markdown,
            surfaceId: "surface-markdown-1",
            title: "Agent output"
        )
        store.dispatch(
            .presentAgentSurface(surface, pane: .primary),
            source: "unit_test_agent_surface"
        )

        let snapshot = makeSnapshot(
            isCompactLayout: false,
            sidebarSelection: .notes,
            primarySection: .notes,
            secondarySection: .chat,
            phoneSelection: nil,
            activeSection: .notes,
            focusedSection: .notes
        )
        store.syncLegacySnapshot(
            WorkspaceLegacySnapshot(
                mode: .agent,
                isCompactLayout: snapshot.isCompactLayout,
                sidebarSelection: snapshot.sidebarSelection,
                primarySection: snapshot.primarySection,
                secondarySection: snapshot.secondarySection,
                phoneSelection: snapshot.phoneSelection,
                activeSection: snapshot.activeSection,
                focusedSection: snapshot.focusedSection,
                lastNonChatSection: snapshot.lastNonChatSection,
                isLeftPanelExpanded: snapshot.isLeftPanelExpanded,
                isWorkspaceExpanded: snapshot.isWorkspaceExpanded,
                isWorkspaceExpandedByRotation: snapshot.isWorkspaceExpandedByRotation,
                isSettingsPresented: snapshot.isSettingsPresented
            ),
            source: "unit_test_legacy_sync_agent"
        )

        XCTAssertEqual(store.state.mode, .agent)
        XCTAssertEqual(store.state.primaryPane.descriptor, .agentSurface(surface))
        XCTAssertEqual(store.parityDivergenceCount, 0)
    }

    private func makeStore() -> WorkspaceStore {
        let store = WorkspaceStore()
        Self.retainedStores.append(store)
        return store
    }

    private func makeSnapshot(
        isCompactLayout: Bool,
        sidebarSelection: AppSection?,
        primarySection: AppSection?,
        secondarySection: AppSection?,
        phoneSelection: AppSection?,
        activeSection: AppSection?,
        focusedSection: AppSection?
    ) -> WorkspaceLegacySnapshot {
        WorkspaceLegacySnapshot(
            isCompactLayout: isCompactLayout,
            sidebarSelection: sidebarSelection,
            primarySection: primarySection,
            secondarySection: secondarySection,
            phoneSelection: phoneSelection,
            activeSection: activeSection,
            focusedSection: focusedSection,
            lastNonChatSection: primarySection,
            isLeftPanelExpanded: true,
            isWorkspaceExpanded: false,
            isWorkspaceExpandedByRotation: false,
            isSettingsPresented: false
        )
    }
}
// swiftlint:enable type_body_length

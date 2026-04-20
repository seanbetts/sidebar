import Foundation
import Combine
import sideBarShared

enum WorkspaceReducer {
    static func reduce(state: WorkspaceState, action: WorkspaceAction) -> WorkspaceState {
        var next = state
        apply(action, state: &next)
        reconcileModeForContent(state: &next)
        return next
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func apply(
        _ action: WorkspaceAction,
        state: inout WorkspaceState
    ) {
        switch action {
        case .setMode(let mode):
            state.mode = mode

        case .applyLegacySnapshot(let snapshot):
            if snapshot.mode == .agent || state.mode == .agent {
                applyLegacySnapshotPreservingAgentContent(snapshot, state: &state)
            } else {
                state = WorkspaceState.fromLegacySnapshot(snapshot)
            }

        case .selectSection(let section):
            applySectionSelection(section, state: &state)

        case .setLayout(let layout):
            applyLayout(layout, state: &state)

        case .setLeftPanelExpanded(let isExpanded):
            state.isLeftPanelExpanded = isExpanded

        case .setWorkspaceExpanded(let isExpanded):
            state.isWorkspaceExpanded = isExpanded

        case .setWorkspaceExpandedByRotation(let isExpandedByRotation):
            state.isWorkspaceExpandedByRotation = isExpandedByRotation

        case .setSettingsPresented(let isPresented):
            state.isSettingsPresented = isPresented

        case .setPrimaryContent(let descriptor):
            state.primaryPane.descriptor = descriptor

        case .setSecondaryContent(let descriptor):
            applySecondaryContent(descriptor, state: &state)

        case .presentAgentSurface(let surface, let pane):
            applyPresentedAgentSurface(surface, pane: pane, state: &state)

        case .closePane(let pane):
            applyClosedPane(pane, state: &state)

        case .setAgentSurfacePinned(let surfaceId, let isPinned):
            applySurfacePinnedState(
                surfaceId: surfaceId,
                isPinned: isPinned,
                state: &state
            )

        case .swapPanes:
            applySwap(state: &state)
        }
    }

    private static func applyLegacySnapshotPreservingAgentContent(
        _ snapshot: WorkspaceLegacySnapshot,
        state: inout WorkspaceState
    ) {
        state.mode = snapshot.mode
        applyLayout(snapshot.isCompactLayout ? .compact : .split, state: &state)
        state.sidebarSelection = snapshot.sidebarSelection
        state.activeSection = snapshot.activeSection
        state.focusedSection = snapshot.focusedSection
        state.lastNonChatSection = snapshot.lastNonChatSection
        state.isLeftPanelExpanded = snapshot.isLeftPanelExpanded
        state.isWorkspaceExpanded = snapshot.isWorkspaceExpanded
        state.isWorkspaceExpandedByRotation = snapshot.isWorkspaceExpandedByRotation
        state.isSettingsPresented = snapshot.isSettingsPresented
    }

    private static func applyLayout(
        _ layout: WorkspaceLayoutMode,
        state: inout WorkspaceState
    ) {
        state.layout = layout
        if layout == .compact {
            state.secondaryPane = nil
        } else if state.secondaryPane == nil {
            state.secondaryPane = WorkspacePaneState(
                pane: .secondary,
                descriptor: .empty
            )
        }
    }

    private static func applySecondaryContent(
        _ descriptor: WorkspaceContentDescriptor?,
        state: inout WorkspaceState
    ) {
        guard let descriptor else {
            state.secondaryPane = nil
            return
        }
        state.secondaryPane = WorkspacePaneState(
            pane: .secondary,
            descriptor: descriptor
        )
    }

    private static func applySwap(
        state: inout WorkspaceState
    ) {
        guard let secondaryPane = state.secondaryPane else { return }
        let previousPrimaryDescriptor = state.primaryPane.descriptor
        state.primaryPane.descriptor = secondaryPane.descriptor
        state.secondaryPane?.descriptor = previousPrimaryDescriptor
        if let primarySection = WorkspaceLegacySectionAdapter.section(
            from: state.primaryPane.descriptor
        ), primarySection != .chat {
            state.lastNonChatSection = primarySection
        }
    }

    // Workaround for a Swift optimizer ownership-verifier crash seen in archive builds.
    @_optimize(none)
    private static func applySectionSelection(
        _ section: AppSection,
        state: inout WorkspaceState
    ) {
        // Snapshot descriptors up-front to avoid borrow/mutation overlap on `state`.
        let primaryDescriptor = state.primaryPane.descriptor
        let secondaryDescriptor = state.secondaryPane?.descriptor
        let currentPrimarySection = WorkspaceLegacySectionAdapter.section(
            from: primaryDescriptor
        )
        let currentSecondarySection = WorkspaceLegacySectionAdapter.section(
            from: secondaryDescriptor
        )

        state.mode = .core
        state.sidebarSelection = section
        state.activeSection = section
        state.focusedSection = section

        if state.layout == .compact {
            state.primaryPane.descriptor = .builtIn(section)
            state.secondaryPane = nil
            if section != .chat {
                state.lastNonChatSection = section
            }
            return
        }

        if section == .chat {
            state.primaryPane.descriptor = .empty
            state.secondaryPane = WorkspacePaneState(
                pane: .secondary,
                descriptor: .builtIn(.chat)
            )
            return
        }

        if currentPrimarySection == .chat {
            state.primaryPane.descriptor = .builtIn(.chat)
            state.secondaryPane = WorkspacePaneState(
                pane: .secondary,
                descriptor: .builtIn(section)
            )
        } else {
            state.primaryPane.descriptor = .builtIn(section)
            state.secondaryPane = WorkspacePaneState(
                pane: .secondary,
                descriptor: .fromOptionalBuiltInSection(currentSecondarySection)
            )
        }
        state.lastNonChatSection = section
    }

    private static func applyPresentedAgentSurface(
        _ surface: AgentWorkspaceSurfaceDescriptor,
        pane: WorkspacePane,
        state: inout WorkspaceState
    ) {
        state.mode = .agent

        if shouldPreserveCollaborativeSurface(surface, in: pane, state: state) {
            mergeCollaborativeSurface(surface, in: pane, state: &state)
            return
        }

        let descriptor = WorkspaceContentDescriptor.agentSurface(surface)
        switch pane {
        case .primary:
            state.primaryPane.descriptor = descriptor
        case .secondary:
            if state.layout == .compact {
                state.primaryPane.descriptor = descriptor
            } else {
                state.secondaryPane = WorkspacePaneState(
                    pane: .secondary,
                    descriptor: descriptor
                )
            }
        }
    }

    private static func shouldPreserveCollaborativeSurface(
        _ incoming: AgentWorkspaceSurfaceDescriptor,
        in pane: WorkspacePane,
        state: WorkspaceState
    ) -> Bool {
        guard incoming.surfaceClass == .boundEntity,
              incoming.authorityMode == .collaborative,
              let incomingBoundEntity = incoming.boundEntity,
              let current = currentSurface(in: pane, state: state),
              current.surfaceClass == .boundEntity,
              current.authorityMode == .collaborative,
              let currentBoundEntity = current.boundEntity else {
            return false
        }

        return currentBoundEntity == incomingBoundEntity
    }

    private static func mergeCollaborativeSurface(
        _ incoming: AgentWorkspaceSurfaceDescriptor,
        in pane: WorkspacePane,
        state: inout WorkspaceState
    ) {
        guard let current = currentSurface(in: pane, state: state) else { return }

        let merged = AgentWorkspaceSurfaceDescriptor(
            type: incoming.type,
            surfaceId: incoming.surfaceId,
            title: incoming.title,
            payload: current.payload,
            contextMenuActions: incoming.contextMenuActions,
            surfaceClass: incoming.surfaceClass,
            authorityMode: incoming.authorityMode,
            boundEntity: incoming.boundEntity,
            collaborationScope: incoming.collaborationScope,
            capabilities: current.capabilities,
            isPinned: current.isPinned
        )

        setSurface(merged, in: pane, state: &state)
    }

    private static func applyClosedPane(
        _ pane: WorkspacePane,
        state: inout WorkspaceState
    ) {
        switch pane {
        case .primary:
            state.primaryPane.descriptor = .empty
        case .secondary:
            if state.layout == .compact {
                state.primaryPane.descriptor = .empty
            } else {
                state.secondaryPane = WorkspacePaneState(
                    pane: .secondary,
                    descriptor: .empty
                )
            }
        }
    }

    private static func applySurfacePinnedState(
        surfaceId: String,
        isPinned: Bool,
        state: inout WorkspaceState
    ) {
        updateSurface(in: &state.primaryPane.descriptor, surfaceId: surfaceId) { surface in
            var updated = surface
            updated.isPinned = isPinned
            return updated
        }
        if var secondaryPane = state.secondaryPane {
            updateSurface(
                in: &secondaryPane.descriptor,
                surfaceId: surfaceId
            ) { surface in
                var updated = surface
                updated.isPinned = isPinned
                return updated
            }
            state.secondaryPane = secondaryPane
        }
    }

    private static func updateSurface(
        in descriptor: inout WorkspaceContentDescriptor,
        surfaceId: String,
        updater: (AgentWorkspaceSurfaceDescriptor) -> AgentWorkspaceSurfaceDescriptor
    ) {
        guard case .agentSurface(let surface) = descriptor,
              surface.surfaceId == surfaceId else { return }
        descriptor = .agentSurface(updater(surface))
    }

    private static func currentSurface(
        in pane: WorkspacePane,
        state: WorkspaceState
    ) -> AgentWorkspaceSurfaceDescriptor? {
        switch pane {
        case .primary:
            guard case .agentSurface(let surface) = state.primaryPane.descriptor else {
                return nil
            }
            return surface

        case .secondary:
            let descriptor = state.layout == .compact
                ? state.primaryPane.descriptor
                : state.secondaryPane?.descriptor
            guard case .agentSurface(let surface) = descriptor else {
                return nil
            }
            return surface
        }
    }

    private static func setSurface(
        _ surface: AgentWorkspaceSurfaceDescriptor,
        in pane: WorkspacePane,
        state: inout WorkspaceState
    ) {
        let descriptor = WorkspaceContentDescriptor.agentSurface(surface)
        switch pane {
        case .primary:
            state.primaryPane.descriptor = descriptor

        case .secondary:
            if state.layout == .compact {
                state.primaryPane.descriptor = descriptor
            } else {
                state.secondaryPane = WorkspacePaneState(
                    pane: .secondary,
                    descriptor: descriptor
                )
            }
        }
    }

    private static func hasAgentSurface(_ descriptor: WorkspaceContentDescriptor?) -> Bool {
        guard let descriptor else { return false }
        if case .agentSurface = descriptor {
            return true
        }
        return false
    }

    private static func reconcileModeForContent(
        state: inout WorkspaceState
    ) {
        let containsAgentSurface = hasAgentSurface(state.primaryPane.descriptor)
            || hasAgentSurface(state.secondaryPane?.descriptor)
        state.mode = containsAgentSurface ? .agent : .core
    }
}

/// Shadow workspace source-of-truth used during migration from legacy `ContentView` state.
public final class WorkspaceStore: ObservableObject {
    @Published public private(set) var state: WorkspaceState
    @Published public private(set) var parityDivergenceCount: Int = 0
    @Published public private(set) var lastParityDivergence: String?

    private var lastLegacySnapshot: WorkspaceLegacySnapshot?

    public init(initialState: WorkspaceState = WorkspaceState()) {
        self.state = initialState
    }

    public func dispatch(
        _ action: WorkspaceAction,
        source: String = "workspace_action"
    ) {
        let nextState = WorkspaceReducer.reduce(state: state, action: action)
        guard nextState != state else { return }
        state = nextState
        guard case .applyLegacySnapshot = action else {
            verifyParityIfNeeded(source: source)
            return
        }
    }

    public func syncLegacySnapshot(
        _ snapshot: WorkspaceLegacySnapshot,
        source: String = "legacy_content_view"
    ) {
        lastLegacySnapshot = snapshot
        dispatch(.applyLegacySnapshot(snapshot), source: source)
        verifyParityIfNeeded(source: source)
    }

    private func verifyParityIfNeeded(source: String) {
        guard let snapshot = lastLegacySnapshot else { return }
        guard state.mode == .core, snapshot.mode == .core else { return }
        let expected = WorkspaceState.expectedParityProjection(from: snapshot)
        guard state.parityProjection != expected else { return }

        let message = """
        Shadow parity divergence (\(source)):
        expected={\(Self.describe(expected))}
        actual={\(Self.describe(state.parityProjection))}
        """
        lastParityDivergence = message
        parityDivergenceCount += 1
        if !EnvironmentConfig.isRunningTestsOrPreviews() {
            assertionFailure(message)
        }
    }

    private static func describe(_ projection: WorkspaceParityProjection) -> String {
        [
            "layout=\(projection.layout.rawValue)",
            "primary=\(describe(projection.primaryDescriptor))",
            "secondary=\(describe(projection.secondaryDescriptor))",
            "sidebar=\(projection.sidebarSelection?.rawValue ?? "nil")",
            "active=\(projection.activeSection?.rawValue ?? "nil")",
            "focused=\(projection.focusedSection?.rawValue ?? "nil")",
            "lastNonChat=\(projection.lastNonChatSection?.rawValue ?? "nil")",
            "leftExpanded=\(projection.isLeftPanelExpanded)",
            "workspaceExpanded=\(projection.isWorkspaceExpanded)",
            "expandedByRotation=\(projection.isWorkspaceExpandedByRotation)",
            "settingsPresented=\(projection.isSettingsPresented)"
        ].joined(separator: ", ")
    }

    private static func describe(_ descriptor: WorkspaceContentDescriptor?) -> String {
        guard let descriptor else { return "nil" }
        return describe(descriptor)
    }

    private static func describe(_ descriptor: WorkspaceContentDescriptor) -> String {
        switch descriptor {
        case .empty:
            return "empty"
        case .builtIn(let section):
            return "builtIn:\(section.rawValue)"
        case .agentSurface(let surface):
            return "agentSurface:\(surface.type):\(surface.surfaceId)"
        }
    }
}

import Foundation
import Combine
import sideBarShared

enum WorkspaceReducer {
    static func reduce(state: WorkspaceState, action: WorkspaceAction) -> WorkspaceState {
        var next = state
        switch action {
        case .setMode(let mode):
            next.mode = mode

        case .applyLegacySnapshot(let snapshot):
            next = WorkspaceState.fromLegacySnapshot(snapshot)

        case .selectSection(let section):
            applySectionSelection(section, state: &next)

        case .setLayout(let layout):
            applyLayout(layout, state: &next)

        case .setPrimaryContent(let descriptor):
            next.primaryPane.descriptor = descriptor

        case .setSecondaryContent(let descriptor):
            applySecondaryContent(descriptor, state: &next)

        case .swapPanes:
            applySwap(state: &next)
        }
        return next
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
    }

    private static func applySectionSelection(
        _ section: AppSection,
        state: inout WorkspaceState
    ) {
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

        let currentPrimarySection = WorkspaceLegacySectionAdapter.section(
            from: state.primaryPane.descriptor
        )
        let currentSecondarySection = WorkspaceLegacySectionAdapter.section(
            from: state.secondaryPane?.descriptor
        )

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

    /// Compatibility overload kept during migration so existing call sites and
    /// test bundles linked against the older symbol continue to load.
    public func dispatch(
        _ action: WorkspaceAction,
        source: String = "workspace_action"
    ) {
        dispatch(
            action,
            source: source,
            expectLegacyFollowup: false
        )
    }

    public func dispatch(
        _ action: WorkspaceAction,
        source: String,
        expectLegacyFollowup: Bool
    ) {
        state = WorkspaceReducer.reduce(state: state, action: action)
        guard case .applyLegacySnapshot = action else {
            if expectLegacyFollowup {
                return
            }
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

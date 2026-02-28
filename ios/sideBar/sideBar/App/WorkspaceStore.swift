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

        case .setLayout(let layout):
            next.layout = layout
            if layout == .compact {
                next.secondaryPane = nil
            } else if next.secondaryPane == nil {
                next.secondaryPane = WorkspacePaneState(
                    pane: .secondary,
                    descriptor: .empty
                )
            }

        case .setPrimaryContent(let descriptor):
            next.primaryPane.descriptor = descriptor

        case .setSecondaryContent(let descriptor):
            if let descriptor {
                next.secondaryPane = WorkspacePaneState(
                    pane: .secondary,
                    descriptor: descriptor
                )
            } else {
                next.secondaryPane = nil
            }

        case .swapPanes:
            guard let secondaryPane = next.secondaryPane else { break }
            let previousPrimaryDescriptor = next.primaryPane.descriptor
            next.primaryPane.descriptor = secondaryPane.descriptor
            next.secondaryPane?.descriptor = previousPrimaryDescriptor
        }
        return next
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

    public func dispatch(_ action: WorkspaceAction, source: String = "workspace_action") {
        state = WorkspaceReducer.reduce(state: state, action: action)
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

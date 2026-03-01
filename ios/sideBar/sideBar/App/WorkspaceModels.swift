import Foundation

/// High-level workspace capability envelope.
public enum WorkspaceMode: String, Equatable {
    case core
    case agent
}

/// Current workspace layout mode.
public enum WorkspaceLayoutMode: String, Equatable {
    case split
    case compact
}

/// Identifies a visible workspace pane.
public enum WorkspacePane: String, Equatable {
    case primary
    case secondary
}

/// Metadata for a dynamic agent-rendered surface.
public enum AgentWorkspaceSurfaceType: String, CaseIterable, Equatable {
    case markdown
    case table
    case chart
    case map
    case form
    case actionPanel
}

/// Context-menu actions surfaced for agent-rendered content.
public enum AgentWorkspaceContextMenuAction: String, CaseIterable, Equatable {
    case copyMarkdown = "copy_markdown"
    case shareText = "share_text"
    case download
}

/// Capability flags for agent-rendered surface controls.
public struct AgentWorkspaceSurfaceCapabilities: Equatable {
    public var canRefresh: Bool
    public var canClose: Bool
    public var canPin: Bool
    public var canInspectData: Bool

    public init(
        canRefresh: Bool = true,
        canClose: Bool = true,
        canPin: Bool = true,
        canInspectData: Bool = true
    ) {
        self.canRefresh = canRefresh
        self.canClose = canClose
        self.canPin = canPin
        self.canInspectData = canInspectData
    }
}

public struct AgentWorkspaceSurfaceDescriptor: Equatable {
    public let type: String
    public let surfaceId: String
    public let title: String?
    public let payload: [String: String]
    public let contextMenuActions: [AgentWorkspaceContextMenuAction]
    public var capabilities: AgentWorkspaceSurfaceCapabilities
    public var isPinned: Bool

    public var surfaceType: AgentWorkspaceSurfaceType {
        AgentWorkspaceSurfaceType(rawValue: type) ?? .actionPanel
    }

    public init(
        type: String,
        surfaceId: String,
        title: String? = nil,
        payload: [String: String] = [:],
        contextMenuActions: [AgentWorkspaceContextMenuAction] = [],
        capabilities: AgentWorkspaceSurfaceCapabilities = AgentWorkspaceSurfaceCapabilities(),
        isPinned: Bool = false
    ) {
        self.type = type
        self.surfaceId = surfaceId
        self.title = title
        self.payload = payload
        self.contextMenuActions = contextMenuActions
        self.capabilities = capabilities
        self.isPinned = isPinned
    }

    public init(
        type: AgentWorkspaceSurfaceType,
        surfaceId: String,
        title: String? = nil,
        payload: [String: String] = [:],
        contextMenuActions: [AgentWorkspaceContextMenuAction] = [],
        capabilities: AgentWorkspaceSurfaceCapabilities = AgentWorkspaceSurfaceCapabilities(),
        isPinned: Bool = false
    ) {
        self.init(
            type: type.rawValue,
            surfaceId: surfaceId,
            title: title,
            payload: payload,
            contextMenuActions: contextMenuActions,
            capabilities: capabilities,
            isPinned: isPinned
        )
    }
}

/// Content descriptor rendered inside a workspace pane.
public enum WorkspaceContentDescriptor: Equatable {
    case empty
    case builtIn(AppSection)
    case agentSurface(AgentWorkspaceSurfaceDescriptor)
}

extension WorkspaceContentDescriptor {
    static func fromOptionalBuiltInSection(_ section: AppSection?) -> WorkspaceContentDescriptor {
        guard let section else { return .empty }
        return .builtIn(section)
    }
}

/// Current state for one pane in the workspace.
public struct WorkspacePaneState: Equatable {
    public let pane: WorkspacePane
    public var descriptor: WorkspaceContentDescriptor

    public init(pane: WorkspacePane, descriptor: WorkspaceContentDescriptor) {
        self.pane = pane
        self.descriptor = descriptor
    }
}

/// Snapshot of legacy `ContentView` state mirrored into the workspace store.
public struct WorkspaceLegacySnapshot: Equatable {
    public let mode: WorkspaceMode
    public let isCompactLayout: Bool
    public let sidebarSelection: AppSection?
    public let primarySection: AppSection?
    public let secondarySection: AppSection?
    public let phoneSelection: AppSection?
    public let activeSection: AppSection?
    public let focusedSection: AppSection?
    public let lastNonChatSection: AppSection?
    public let isLeftPanelExpanded: Bool
    public let isWorkspaceExpanded: Bool
    public let isWorkspaceExpandedByRotation: Bool
    public let isSettingsPresented: Bool

    public init(
        mode: WorkspaceMode = .core,
        isCompactLayout: Bool,
        sidebarSelection: AppSection?,
        primarySection: AppSection?,
        secondarySection: AppSection?,
        phoneSelection: AppSection?,
        activeSection: AppSection?,
        focusedSection: AppSection?,
        lastNonChatSection: AppSection?,
        isLeftPanelExpanded: Bool,
        isWorkspaceExpanded: Bool,
        isWorkspaceExpandedByRotation: Bool,
        isSettingsPresented: Bool
    ) {
        self.mode = mode
        self.isCompactLayout = isCompactLayout
        self.sidebarSelection = sidebarSelection
        self.primarySection = primarySection
        self.secondarySection = secondarySection
        self.phoneSelection = phoneSelection
        self.activeSection = activeSection
        self.focusedSection = focusedSection
        self.lastNonChatSection = lastNonChatSection
        self.isLeftPanelExpanded = isLeftPanelExpanded
        self.isWorkspaceExpanded = isWorkspaceExpanded
        self.isWorkspaceExpandedByRotation = isWorkspaceExpandedByRotation
        self.isSettingsPresented = isSettingsPresented
    }
}

/// Canonical workspace state used by the new reducer pipeline.
public struct WorkspaceState: Equatable {
    public var mode: WorkspaceMode
    public var layout: WorkspaceLayoutMode
    public var primaryPane: WorkspacePaneState
    public var secondaryPane: WorkspacePaneState?
    public var sidebarSelection: AppSection?
    public var activeSection: AppSection?
    public var focusedSection: AppSection?
    public var lastNonChatSection: AppSection?
    public var isLeftPanelExpanded: Bool
    public var isWorkspaceExpanded: Bool
    public var isWorkspaceExpandedByRotation: Bool
    public var isSettingsPresented: Bool

    public init(
        mode: WorkspaceMode = .core,
        layout: WorkspaceLayoutMode = .split,
        primaryPane: WorkspacePaneState = WorkspacePaneState(
            pane: .primary,
            descriptor: .empty
        ),
        secondaryPane: WorkspacePaneState? = WorkspacePaneState(
            pane: .secondary,
            descriptor: .builtIn(.chat)
        ),
        sidebarSelection: AppSection? = .chat,
        activeSection: AppSection? = .chat,
        focusedSection: AppSection? = nil,
        lastNonChatSection: AppSection? = nil,
        isLeftPanelExpanded: Bool = true,
        isWorkspaceExpanded: Bool = false,
        isWorkspaceExpandedByRotation: Bool = false,
        isSettingsPresented: Bool = false
    ) {
        self.mode = mode
        self.layout = layout
        self.primaryPane = primaryPane
        self.secondaryPane = secondaryPane
        self.sidebarSelection = sidebarSelection
        self.activeSection = activeSection
        self.focusedSection = focusedSection
        self.lastNonChatSection = lastNonChatSection
        self.isLeftPanelExpanded = isLeftPanelExpanded
        self.isWorkspaceExpanded = isWorkspaceExpanded
        self.isWorkspaceExpandedByRotation = isWorkspaceExpandedByRotation
        self.isSettingsPresented = isSettingsPresented
    }
}

/// Typed workspace mutations used by the reducer.
public enum WorkspaceAction: Equatable {
    case setMode(WorkspaceMode)
    case applyLegacySnapshot(WorkspaceLegacySnapshot)
    case selectSection(AppSection)
    case setLayout(WorkspaceLayoutMode)
    case setLeftPanelExpanded(Bool)
    case setWorkspaceExpanded(Bool)
    case setWorkspaceExpandedByRotation(Bool)
    case setSettingsPresented(Bool)
    case setPrimaryContent(WorkspaceContentDescriptor)
    case setSecondaryContent(WorkspaceContentDescriptor?)
    case presentAgentSurface(AgentWorkspaceSurfaceDescriptor, pane: WorkspacePane)
    case closePane(WorkspacePane)
    case setAgentSurfacePinned(surfaceId: String, isPinned: Bool)
    case swapPanes
}

struct WorkspaceParityProjection: Equatable {
    let layout: WorkspaceLayoutMode
    let primaryDescriptor: WorkspaceContentDescriptor
    let secondaryDescriptor: WorkspaceContentDescriptor?
    let sidebarSelection: AppSection?
    let activeSection: AppSection?
    let focusedSection: AppSection?
    let lastNonChatSection: AppSection?
    let isLeftPanelExpanded: Bool
    let isWorkspaceExpanded: Bool
    let isWorkspaceExpandedByRotation: Bool
    let isSettingsPresented: Bool
}

extension WorkspaceState {
    static func fromLegacySnapshot(_ snapshot: WorkspaceLegacySnapshot) -> WorkspaceState {
        let layout: WorkspaceLayoutMode = snapshot.isCompactLayout ? .compact : .split
        let compactSection = snapshot.phoneSelection ?? snapshot.sidebarSelection ?? snapshot.activeSection ?? .chat
        let primaryDescriptor: WorkspaceContentDescriptor = snapshot.isCompactLayout
            ? .builtIn(compactSection)
            : .fromOptionalBuiltInSection(snapshot.primarySection)
        let secondaryPane: WorkspacePaneState? = snapshot.isCompactLayout
            ? nil
            : WorkspacePaneState(
                pane: .secondary,
                descriptor: .fromOptionalBuiltInSection(snapshot.secondarySection)
            )

        return WorkspaceState(
            mode: snapshot.mode,
            layout: layout,
            primaryPane: WorkspacePaneState(
                pane: .primary,
                descriptor: primaryDescriptor
            ),
            secondaryPane: secondaryPane,
            sidebarSelection: snapshot.sidebarSelection,
            activeSection: snapshot.activeSection,
            focusedSection: snapshot.focusedSection,
            lastNonChatSection: snapshot.lastNonChatSection,
            isLeftPanelExpanded: snapshot.isLeftPanelExpanded,
            isWorkspaceExpanded: snapshot.isWorkspaceExpanded,
            isWorkspaceExpandedByRotation: snapshot.isWorkspaceExpandedByRotation,
            isSettingsPresented: snapshot.isSettingsPresented
        )
    }

    var parityProjection: WorkspaceParityProjection {
        WorkspaceParityProjection(
            layout: layout,
            primaryDescriptor: primaryPane.descriptor,
            secondaryDescriptor: secondaryPane?.descriptor,
            sidebarSelection: sidebarSelection,
            activeSection: activeSection,
            focusedSection: focusedSection,
            lastNonChatSection: lastNonChatSection,
            isLeftPanelExpanded: isLeftPanelExpanded,
            isWorkspaceExpanded: isWorkspaceExpanded,
            isWorkspaceExpandedByRotation: isWorkspaceExpandedByRotation,
            isSettingsPresented: isSettingsPresented
        )
    }

    static func expectedParityProjection(
        from snapshot: WorkspaceLegacySnapshot
    ) -> WorkspaceParityProjection {
        fromLegacySnapshot(snapshot).parityProjection
    }
}

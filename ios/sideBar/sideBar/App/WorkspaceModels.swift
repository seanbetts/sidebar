import Foundation
import sideBarShared

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

public enum AgentWorkspaceSurfaceClass: String, Equatable {
    case display = "display"
    case boundEntity = "bound_entity"
    case interactiveBlock = "interactive_block"
}

public enum AgentWorkspaceAuthorityMode: String, Equatable {
    case readOnly = "read_only"
    case userEditable = "user_editable"
    case collaborative = "collaborative"
}

public struct AgentWorkspaceBoundEntityReference: Equatable {
    public let entityType: String
    public let entityId: String

    public init(entityType: String, entityId: String) {
        self.entityType = entityType
        self.entityId = entityId
    }
}

public struct WorkspaceEntityReference: Equatable {
    public let type: String
    public let id: String
    public let title: String?

    public init(type: String, id: String, title: String? = nil) {
        self.type = type
        self.id = id
        self.title = title
    }
}

public struct WorkspaceEntityOpenRequest: Equatable {
    public let entity: WorkspaceEntityReference
    public let routeURL: URL?
    public let section: AppSection?
    public let pane: WorkspacePane

    public init(
        entity: WorkspaceEntityReference,
        routeURL: URL?,
        section: AppSection?,
        pane: WorkspacePane = .primary
    ) {
        self.entity = entity
        self.routeURL = routeURL
        self.section = section
        self.pane = pane
    }
}

public enum AgentWorkspaceCollaborationScope: Equatable {
    case none
    case conversationBoundEntity(entityType: String, entityId: String)
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

public struct AgentWorkspaceChartPoint: Equatable, Identifiable {
    public let id: String
    public let label: String
    public let value: Double

    public init(id: String? = nil, label: String, value: Double) {
        let normalizedId = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = normalizedId?.isEmpty == false ? normalizedId! : "\(label)-\(value)"
        self.label = label
        self.value = value
    }
}

public struct AgentWorkspaceMapLocation: Equatable, Identifiable {
    public let id: String
    public let latitude: Double
    public let longitude: Double
    public let label: String?

    public init(id: String? = nil, latitude: Double, longitude: Double, label: String? = nil) {
        let normalizedId = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = normalizedId?.isEmpty == false ? normalizedId! : "\(latitude),\(longitude)"
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
    }
}

public struct AgentWorkspaceFormField: Equatable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let placeholder: String?

    public init(id: String, label: String, value: String, placeholder: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.placeholder = placeholder
    }
}

public struct AgentWorkspaceActionItem: Equatable, Identifiable {
    public enum Style: String, Equatable {
        case primary
        case secondary
    }

    public let id: String
    public let title: String
    public let systemImage: String?
    public let style: Style

    public init(
        id: String,
        title: String,
        systemImage: String? = nil,
        style: Style = .secondary
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.style = style
    }
}

public struct AgentWorkspaceSurfaceDescriptor: Equatable {
    public let type: String
    public let surfaceId: String
    public let title: String?
    public let payload: [String: String]
    public let contextMenuActions: [AgentWorkspaceContextMenuAction]
    public let surfaceClass: AgentWorkspaceSurfaceClass
    public let authorityMode: AgentWorkspaceAuthorityMode
    public let boundEntity: AgentWorkspaceBoundEntityReference?
    public let collaborationScope: AgentWorkspaceCollaborationScope
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
        surfaceClass: AgentWorkspaceSurfaceClass = .display,
        authorityMode: AgentWorkspaceAuthorityMode = .readOnly,
        boundEntity: AgentWorkspaceBoundEntityReference? = nil,
        collaborationScope: AgentWorkspaceCollaborationScope = .none,
        capabilities: AgentWorkspaceSurfaceCapabilities = AgentWorkspaceSurfaceCapabilities(),
        isPinned: Bool = false
    ) {
        self.type = type
        self.surfaceId = surfaceId
        self.title = title
        self.payload = payload
        self.contextMenuActions = contextMenuActions
        self.surfaceClass = surfaceClass
        self.authorityMode = authorityMode
        self.boundEntity = boundEntity
        self.collaborationScope = collaborationScope
        self.capabilities = capabilities
        self.isPinned = isPinned
    }

    public init(
        type: AgentWorkspaceSurfaceType,
        surfaceId: String,
        title: String? = nil,
        payload: [String: String] = [:],
        contextMenuActions: [AgentWorkspaceContextMenuAction] = [],
        surfaceClass: AgentWorkspaceSurfaceClass = .display,
        authorityMode: AgentWorkspaceAuthorityMode = .readOnly,
        boundEntity: AgentWorkspaceBoundEntityReference? = nil,
        collaborationScope: AgentWorkspaceCollaborationScope = .none,
        capabilities: AgentWorkspaceSurfaceCapabilities = AgentWorkspaceSurfaceCapabilities(),
        isPinned: Bool = false
    ) {
        self.init(
            type: type.rawValue,
            surfaceId: surfaceId,
            title: title,
            payload: payload,
            contextMenuActions: contextMenuActions,
            surfaceClass: surfaceClass,
            authorityMode: authorityMode,
            boundEntity: boundEntity,
            collaborationScope: collaborationScope,
            capabilities: capabilities,
            isPinned: isPinned
        )
    }

    public var chartPoints: [AgentWorkspaceChartPoint] {
        if let points: [ChartPointPayload] = payload.decodeJSON(
            [ChartPointPayload].self,
            forKeys: ["points", "data_points", "series"]
        ) {
            let resolved = points.compactMap(\.resolvedPoint)
            if !resolved.isEmpty {
                return resolved
            }
        }

        let labels = payload.stringArray(forKeys: ["x_values", "xValues", "labels"])
        let values = payload.doubleArray(forKeys: ["y_values", "yValues", "values"])
        guard !labels.isEmpty, !values.isEmpty else {
            return []
        }

        return Array(zip(labels, values)).map { label, value in
            AgentWorkspaceChartPoint(label: label, value: value)
        }
    }

    public var mapLocation: AgentWorkspaceMapLocation? {
        guard let latitude = payload.doubleValue(forKeys: ["latitude", "lat"]),
              let longitude = payload.doubleValue(forKeys: ["longitude", "lon", "lng"]) else {
            return nil
        }

        return AgentWorkspaceMapLocation(
            id: surfaceId,
            latitude: latitude,
            longitude: longitude,
            label: payload.firstTrimmedString(forKeys: ["label", "location", "title"])
        )
    }

    public var formFields: [AgentWorkspaceFormField] {
        if let fields: [FormFieldPayload] = payload.decodeJSON([FormFieldPayload].self, forKeys: ["fields"]) {
            let resolved = fields.compactMap(\.resolvedField)
            if !resolved.isEmpty {
                return resolved
            }
        }

        let fallbackKeys = payload.keys
            .filter { $0.hasPrefix("field_") && !$0.hasSuffix("_label") && !$0.hasSuffix("_placeholder") }
            .sorted()

        return fallbackKeys.compactMap { key in
            let value = payload[key] ?? ""
            let label = payload["\(key)_label"]?.trimmedOrNil ?? humanizedLabel(from: key)
            return AgentWorkspaceFormField(
                id: key,
                label: label,
                value: value,
                placeholder: payload["\(key)_placeholder"]?.trimmedOrNil
            )
        }
    }

    public var actionItems: [AgentWorkspaceActionItem] {
        if let items: [ActionItemPayload] = payload.decodeJSON(
            [ActionItemPayload].self,
            forKeys: ["actions", "buttons"]
        ) {
            let resolved = items.compactMap(\.resolvedItem)
            if !resolved.isEmpty {
                return resolved
            }
        }

        var fallback: [AgentWorkspaceActionItem] = []
        if let primary = payload["primary_action"]?.trimmedOrNil {
            fallback.append(
                AgentWorkspaceActionItem(id: "primary_action", title: primary, style: .primary)
            )
        }
        if let secondary = payload["secondary_action"]?.trimmedOrNil {
            fallback.append(
                AgentWorkspaceActionItem(id: "secondary_action", title: secondary, style: .secondary)
            )
        }
        return fallback
    }

    public var supportsEphemeralInteraction: Bool {
        surfaceClass == .interactiveBlock && authorityMode != .readOnly
    }

    private func humanizedLabel(from rawKey: String) -> String {
        rawKey
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
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
    case openEntity(WorkspaceEntityOpenRequest)
    case closePane(WorkspacePane)
    case setAgentSurfacePinned(surfaceId: String, isPinned: Bool)
    case swapPanes
}

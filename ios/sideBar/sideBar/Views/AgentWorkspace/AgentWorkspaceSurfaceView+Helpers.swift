import Charts
import MapKit
import SwiftUI
import UniformTypeIdentifiers
import sideBarShared
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension AgentWorkspaceSurfaceView {
    var resolvedTitle: String {
        let title = surface.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            return "Agent Workspace"
        }
        return title
    }

    var surfaceLabel: String {
        var label = surface.surfaceType.rawValue
        label = label.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    var shouldShowExpandButton: Bool {
        WorkspaceBehaviorPolicy.shouldShowExpandButton(
            workspaceColumn: workspaceColumn,
            isPhoneIdiom: {
                #if os(iOS)
                isPhone
                #else
                false
                #endif
            }()
        )
    }

    var expandButton: some View {
        HeaderActionButton(
            icon: expandButtonIcon,
            accessibilityLabel: expandButtonLabel,
            action: expandWorkspaceView
        )
    }

    var expandButtonIcon: AppIcon {
        isWorkspaceExpanded
            ? AppIcon.Navigation.expandWorkspace
            : AppIcon.Navigation.collapseWorkspace
    }

    var expandButtonLabel: String {
        isWorkspaceExpanded ? "Exit expanded mode" : "Expand workspace"
    }

    func expandWorkspaceView() {
        #if os(iOS)
        if !isPhone {
            isWorkspaceExpandedByRotation = false
        }
        #endif
        isWorkspaceExpanded.toggle()
    }

    #if os(iOS)
    var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif

    func refreshSurface() {
        environment.toastCenter.show(message: "Agent surface refreshed.", style: .success)
    }

    func closeSurface() {
        environment.closeWorkspacePane(workspacePane, source: "agent_surface_close")
    }

    func copyMarkdownPayload() {
        guard let markdown = markdownPayload else { return }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = markdown
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(iOS)
            let pasteboard = UIPasteboard.general
            if pasteboard.string == markdown {
                pasteboard.string = ""
            }
            #elseif os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == markdown {
                pasteboard.clearContents()
            }
            #endif
        }
    }

    func shareSurfaceText() {
        guard let text = sharableTextPayload else { return }
        SystemSharePresenter.share(
            text: text,
            anchorID: SystemShareAnchorID.workspaceSurfaceActionsMenu(surface.surfaceId)
        )
    }

    func downloadMarkdownPayload() {
        guard let markdown = markdownPayload else { return }
        exportFilename = exportMarkdownFilename
        exportDocument = MarkdownFileDocument(text: markdown)
        isExporting = true
    }

    var markdownPayload: String? {
        if let markdown = surface.payload["markdown"]?.trimmedOrNil {
            return markdown
        }
        if let text = surface.payload["text"]?.trimmedOrNil {
            return text
        }
        return nil
    }

    var sharableTextPayload: String? {
        if let markdown = markdownPayload {
            return markdown
        }
        if let summary = surface.payload["summary"]?.trimmedOrNil {
            return summary
        }
        return nil
    }

    var exportMarkdownFilename: String {
        let base = (surface.title?.trimmedOrNil ?? surface.surfaceId).replacingOccurrences(of: " ", with: "-")
        let sanitized = base.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "-",
            options: .regularExpression
        )
        if sanitized.hasSuffix(".md") {
            return sanitized
        }
        return "\(sanitized).md"
    }

    var chartPoints: [AgentWorkspaceChartPoint] {
        surface.chartPoints
    }

    var mapLocation: AgentWorkspaceMapLocation? {
        surface.mapLocation
    }

    var formFields: [AgentWorkspaceFormField] {
        surface.formFields
    }

    var actionItems: [AgentWorkspaceActionItem] {
        surface.actionItems
    }

    var surfaceSummaryText: String? {
        surface.payload["summary"]?.trimmedOrNil
    }

    var interactionNote: String? {
        if surface.supportsEphemeralInteraction {
            return "Inputs stay local to this workspace surface in v1."
        }
        if surface.surfaceClass == .boundEntity {
            return "Bound entity collaboration will keep using the dedicated editor path in v1."
        }
        return nil
    }

    func appIcon(for type: AgentWorkspaceSurfaceType) -> AppIcon {
        switch type {
        case .markdown:
            return AppIcon.Workspace.markdownSurface
        case .table:
            return AppIcon.Workspace.tableSurface
        case .chart:
            return AppIcon.Workspace.chartSurface
        case .map:
            return AppIcon.Workspace.mapSurface
        case .form:
            return AppIcon.Workspace.formSurface
        case .actionPanel:
            return AppIcon.Workspace.actionPanelSurface
        }
    }

    var workspacePane: WorkspacePane {
        switch workspaceColumn {
        case .primary:
            return .primary
        case .secondary:
            return .secondary
        }
    }

    func binding(for field: AgentWorkspaceFormField) -> Binding<String> {
        Binding(
            get: { ephemeralFieldValues[field.id] ?? field.value },
            set: { ephemeralFieldValues[field.id] = $0 }
        )
    }

    @ViewBuilder
    func actionButton(for action: AgentWorkspaceActionItem) -> some View {
        if action.style == .primary {
            baseActionButton(for: action)
                .buttonStyle(.borderedProminent)
        } else {
            baseActionButton(for: action)
                .buttonStyle(.bordered)
        }
    }

    func baseActionButton(for action: AgentWorkspaceActionItem) -> some View {
        Button {
            guard surface.supportsEphemeralInteraction else { return }
            lastTriggeredActionTitle = action.title
            environment.toastCenter.show(message: "\(action.title) captured locally.", style: .success)
        } label: {
            HStack(spacing: DesignTokens.Spacing.xsPlus) {
                if let appIcon = action.appIcon {
                    Image(appIcon: appIcon)
                }
                Text(action.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!surface.supportsEphemeralInteraction)
    }

    func mapCoordinate(for location: AgentWorkspaceMapLocation) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    func mapCameraPosition(for location: AgentWorkspaceMapLocation) -> MapCameraPosition {
        .region(
            MKCoordinateRegion(
                center: mapCoordinate(for: location),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        )
    }

    func mapMarkerTitle(for location: AgentWorkspaceMapLocation) -> String {
        location.label?.trimmedOrNil ?? resolvedTitle
    }

    @ViewBuilder
    var surfaceActionsMenu: some View {
        #if os(macOS)
        Menu {
            sidebarMenuItemsView(contextMenuItems)
        } label: {
            HeaderActionIcon(icon: AppIcon.Action.more)
        }
        .buttonStyle(.plain)
        .systemShareAnchor(id: SystemShareAnchorID.workspaceSurfaceActionsMenu(surface.surfaceId))
        .accessibilityLabel("Workspace options")
        .disabled(contextMenuItems.isEmpty)
        #else
        HeaderActionMenuButton(
            icon: AppIcon.Action.more,
            accessibilityLabel: "Workspace options",
            items: contextMenuItems,
            isCompact: true
        )
        .systemShareAnchor(id: SystemShareAnchorID.workspaceSurfaceActionsMenu(surface.surfaceId))
        .disabled(contextMenuItems.isEmpty)
        #endif
    }
}

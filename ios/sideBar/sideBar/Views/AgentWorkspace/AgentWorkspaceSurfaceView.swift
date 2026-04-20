import SwiftUI
import Charts
import MapKit
import UniformTypeIdentifiers
import sideBarShared
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AgentWorkspaceSurfaceView: View {
    @EnvironmentObject var environment: AppEnvironment
    @Environment(\.workspaceColumn) var workspaceColumn
    @AppStorage(AppStorageKeys.workspaceExpanded) var isWorkspaceExpanded: Bool = false
    #if os(iOS)
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) var isWorkspaceExpandedByRotation: Bool = false
    #endif

    let surface: AgentWorkspaceSurfaceDescriptor

    @State var exportDocument: MarkdownFileDocument?
    @State var exportFilename = "agent-surface.md"
    @State var isExporting = false
    @State var ephemeralFieldValues: [String: String] = [:]
    @State var lastTriggeredActionTitle: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(DesignTokens.Spacing.lg)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .sideBarMarkdown,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event,
                  event.matches(
                    section: .chat,
                    workspacePane: workspacePane
                  ) else { return }
            guard case .closeItem = event.action else { return }
            guard surface.capabilities.canClose else { return }
            closeSurface()
        }
    }

    private var header: some View {
        ContentHeaderRow(
            iconName: iconName(for: surface.surfaceType),
            title: resolvedTitle,
            subtitle: surfaceLabel,
            titleStyle: .subheadline,
            titleWeight: .semibold,
            titleLineLimit: 1,
            subtitleLineLimit: 1,
            titleSubtitleAxis: .vertical,
            trailing: {
                HeaderActionRow {
                    if shouldShowExpandButton {
                        expandButton
                    }
                    surfaceActionsMenu
                    if surface.capabilities.canRefresh {
                        HeaderActionButton(
                            systemName: "arrow.clockwise",
                            accessibilityLabel: "Refresh surface",
                            action: refreshSurface
                        )
                    }
                    if surface.capabilities.canClose {
                        HeaderActionButton(
                            systemName: "xmark",
                            accessibilityLabel: "Close surface",
                            action: closeSurface
                        )
                        .keyboardShortcut(.escape, modifiers: [])
                    }
                }
            }
        )
        .padding(DesignTokens.Spacing.md)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    var contextMenuItems: [SidebarMenuItem] {
        var items: [SidebarMenuItem] = []

        for action in surface.contextMenuActions {
            switch action {
            case .copyMarkdown:
                items.append(.copyMarkdown { copyMarkdownPayload() })
            case .shareText:
                items.append(.shareText { shareSurfaceText() })
            case .download:
                items.append(.download { downloadMarkdownPayload() })
            }
        }

        if surface.capabilities.canRefresh {
            items.append(
                SidebarMenuItem(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    role: nil,
                    handler: refreshSurface
                )
            )
        }
        if surface.capabilities.canClose {
            items.append(
                SidebarMenuItem(
                    title: "Close",
                    systemImage: "xmark",
                    role: nil,
                    handler: closeSurface
                )
            )
        }

        return items
    }

    @ViewBuilder
    private var content: some View {
        switch surface.surfaceType {
        case .markdown:
            markdownSurface
        case .table:
            tableSurface
        case .chart:
            chartSurface
        case .map:
            mapSurface
        case .form:
            formSurface
        case .actionPanel:
            actionPanelSurface
        }
    }

    private var markdownSurface: some View {
        ScrollView {
            SideBarMarkdown(
                text: surface.payload["markdown"] ?? "No markdown payload provided.",
                renderingContext: .standard
            )
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var tableSurface: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(surface.payload["summary"] ?? "No table data provided.")
                .appFont(.body)
                .foregroundStyle(.secondary)
            if surface.payload.isEmpty {
                EmptyStateView(
                    title: "No table rows",
                    subtitle: "The assistant has not supplied row data yet."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xsPlus) {
                        ForEach(surface.payload.keys.sorted(), id: \.self) { key in
                            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                                Text(key)
                                    .appFont(.captionSemibold)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Text(surface.payload[key] ?? "")
                                    .appFont(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    private var chartSurface: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if chartPoints.isEmpty {
                EmptyStateView(
                    title: "No chart data",
                    subtitle: surfaceSummaryText ?? "The assistant has not supplied chart points yet."
                )
            } else {
                Chart(chartPoints) { point in
                    LineMark(
                        x: .value("Label", point.label),
                        y: .value("Value", point.value)
                    )
                    PointMark(
                        x: .value("Label", point.label),
                        y: .value("Value", point.value)
                    )
                }
                .frame(height: 240)
                .padding(DesignTokens.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(DesignTokens.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
            }

            if let summary = surfaceSummaryText {
                Text(summary)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mapSurface: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if let mapLocation {
                Map(position: .constant(mapCameraPosition(for: mapLocation))) {
                    Marker(mapMarkerTitle(for: mapLocation), coordinate: mapCoordinate(for: mapLocation))
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
            } else {
                EmptyStateView(
                    title: "No map location",
                    subtitle: surfaceSummaryText ?? "The assistant has not supplied map coordinates yet."
                )
            }

            if let summary = surfaceSummaryText {
                Text(summary)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var formSurface: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if let summary = surfaceSummaryText {
                Text(summary)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
            }

            if formFields.isEmpty {
                EmptyStateView(
                    title: "No form fields",
                    subtitle: "The assistant has not supplied form field metadata yet."
                )
            } else {
                ForEach(formFields) { field in
                    TextField(
                        field.label,
                        text: binding(for: field),
                        prompt: field.placeholder.map { Text($0) }
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!surface.supportsEphemeralInteraction)
                }
            }

            if let note = interactionNote {
                Text(note)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionPanelSurface: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if let summary = surfaceSummaryText {
                Text(summary)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
            }

            if actionItems.isEmpty {
                EmptyStateView(
                    title: "No actions available",
                    subtitle: "The assistant has not supplied action metadata yet."
                )
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    ForEach(actionItems) { action in
                        actionButton(for: action)
                    }
                }
            }

            if let lastTriggeredActionTitle {
                Text("Last local action: \(lastTriggeredActionTitle)")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            if let note = interactionNote {
                Text(note)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

}

import SwiftUI

struct AgentWorkspaceSurfaceView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.workspaceColumn) private var workspaceColumn

    let surface: AgentWorkspaceSurfaceDescriptor

    @State private var isInspectingDataPresented = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(DesignTokens.Spacing.lg)
        }
        .contextMenu {
            if surface.capabilities.canRefresh {
                Button("Refresh", systemImage: "arrow.clockwise", action: refreshSurface)
            }
            if surface.capabilities.canPin {
                Button(
                    surface.isPinned ? "Unpin" : "Pin",
                    systemImage: surface.isPinned ? "pin.slash" : "pin"
                ) {
                    togglePinned()
                }
            }
            if surface.capabilities.canInspectData {
                Button("Inspect Data", systemImage: "doc.text.magnifyingglass") {
                    isInspectingDataPresented = true
                }
            }
            if surface.capabilities.canClose {
                Button("Close", systemImage: "xmark") {
                    closeSurface()
                }
            }
        }
        .sheet(isPresented: $isInspectingDataPresented) {
            AgentWorkspaceSurfaceInspectorView(surface: surface)
                .phoneSheetGrabBarVisible()
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
            titleSubtitleAxis: .vertical
        ) {
            HeaderActionRow {
                if surface.capabilities.canRefresh {
                    HeaderActionButton(
                        systemName: "arrow.clockwise",
                        accessibilityLabel: "Refresh surface",
                        action: refreshSurface
                    )
                }
                if surface.capabilities.canPin {
                    HeaderActionButton(
                        systemName: surface.isPinned ? "pin.fill" : "pin",
                        accessibilityLabel: surface.isPinned ? "Unpin surface" : "Pin surface",
                        action: togglePinned
                    )
                }
                if surface.capabilities.canInspectData {
                    HeaderActionButton(
                        systemName: "doc.text.magnifyingglass",
                        accessibilityLabel: "Inspect surface data"
                    ) {
                        isInspectingDataPresented = true
                    }
                }
                if surface.capabilities.canClose {
                    HeaderActionButton(
                        systemName: "xmark",
                        accessibilityLabel: "Close surface",
                        action: closeSurface
                    )
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
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
            Text(surface.payload["markdown"] ?? "No markdown payload provided.")
                .appFont(.body)
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
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(DesignTokens.Colors.surface)
                .overlay {
                    Image(systemName: "chart.xyaxis.line")
                        .appFont(.size32Semibold)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
            Text(surface.payload["summary"] ?? "No chart data provided.")
                .appFont(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var mapSurface: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(DesignTokens.Colors.surface)
                .overlay {
                    VStack(spacing: DesignTokens.Spacing.xsPlus) {
                        Image(systemName: "map")
                            .appFont(.size32Semibold)
                        Text(surface.payload["location"] ?? "Map preview")
                            .appFont(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(height: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                )
            Text(surface.payload["summary"] ?? "No map payload provided.")
                .appFont(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var formSurface: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            TextField("Field one", text: .constant(surface.payload["field_one"] ?? ""))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
            TextField("Field two", text: .constant(surface.payload["field_two"] ?? ""))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
            Text(surface.payload["summary"] ?? "No form payload provided.")
                .appFont(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var actionPanelSurface: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(surface.payload["summary"] ?? "No action panel payload provided.")
                .appFont(.body)
                .foregroundStyle(.secondary)
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button(surface.payload["primary_action"] ?? "Primary Action") {}
                    .buttonStyle(.borderedProminent)
                Button(surface.payload["secondary_action"] ?? "Secondary Action") {}
                    .buttonStyle(.bordered)
            }
        }
    }

    private var resolvedTitle: String {
        let title = surface.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            return "Agent Workspace"
        }
        return title
    }

    private var surfaceLabel: String {
        var label = surface.surfaceType.rawValue
        label = label.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
        label = label.prefix(1).uppercased() + label.dropFirst()
        if surface.isPinned {
            return "\(label) • pinned"
        }
        return label
    }

    private func refreshSurface() {
        environment.toastCenter.show(message: "Agent surface refreshed.", style: .success)
    }

    private func closeSurface() {
        environment.closeWorkspacePane(workspacePane, source: "agent_surface_close")
    }

    private func togglePinned() {
        environment.setAgentSurfacePinned(
            surfaceId: surface.surfaceId,
            isPinned: !surface.isPinned,
            source: "agent_surface_pin_toggle"
        )
    }

    private func iconName(for type: AgentWorkspaceSurfaceType) -> String {
        switch type {
        case .markdown:
            return "doc.plaintext"
        case .table:
            return "tablecells"
        case .chart:
            return "chart.bar.xaxis"
        case .map:
            return "map"
        case .form:
            return "list.bullet.clipboard"
        case .actionPanel:
            return "slider.horizontal.3"
        }
    }

    private var workspacePane: WorkspacePane {
        switch workspaceColumn {
        case .primary:
            return .primary
        case .secondary:
            return .secondary
        }
    }
}

private struct AgentWorkspaceSurfaceInspectorView: View {
    let surface: AgentWorkspaceSurfaceDescriptor

    var body: some View {
        NavigationStack {
            List {
                Section("Surface") {
                    labeledValue("ID", surface.surfaceId)
                    labeledValue("Type", surface.surfaceType.rawValue)
                    labeledValue("Pinned", surface.isPinned ? "Yes" : "No")
                }
                Section("Capabilities") {
                    labeledValue("Refresh", yesNo(surface.capabilities.canRefresh))
                    labeledValue("Close", yesNo(surface.capabilities.canClose))
                    labeledValue("Pin", yesNo(surface.capabilities.canPin))
                    labeledValue("Inspect", yesNo(surface.capabilities.canInspectData))
                }
                Section("Payload") {
                    if surface.payload.isEmpty {
                        Text("No payload values supplied.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(surface.payload.keys.sorted(), id: \.self) { key in
                            labeledValue(key, surface.payload[key] ?? "")
                        }
                    }
                }
            }
            .navigationTitle("Surface Inspector")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    @ViewBuilder
    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .appFont(.captionSemibold)
                .foregroundStyle(.secondary)
            Text(value)
                .appFont(.subheadline)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}

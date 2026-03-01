import SwiftUI
import UniformTypeIdentifiers
import sideBarShared
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AgentWorkspaceSurfaceView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.workspaceColumn) private var workspaceColumn
    @AppStorage(AppStorageKeys.workspaceExpanded) private var isWorkspaceExpanded: Bool = false
    #if os(iOS)
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) private var isWorkspaceExpandedByRotation: Bool = false
    #endif

    let surface: AgentWorkspaceSurfaceDescriptor

    @State private var exportDocument: MarkdownFileDocument?
    @State private var exportFilename = "agent-surface.md"
    @State private var isExporting = false

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

    private var contextMenuItems: [SidebarMenuItem] {
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
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    private var shouldShowExpandButton: Bool {
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

    private var expandButton: some View {
        Button(action: expandWorkspaceView) {
            Image(systemName: expandButtonIconName)
                .appFont(.labelMd)
                .frame(width: 28, height: 20)
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expandButtonLabel)
    }

    private var expandButtonIconName: String {
        isWorkspaceExpanded
            ? "arrow.up.right.and.arrow.down.left"
            : "arrow.down.left.and.arrow.up.right"
    }

    private var expandButtonLabel: String {
        isWorkspaceExpanded ? "Exit expanded mode" : "Expand workspace"
    }

    private func expandWorkspaceView() {
        #if os(iOS)
        if !isPhone {
            isWorkspaceExpandedByRotation = false
        }
        #endif
        isWorkspaceExpanded.toggle()
    }

    #if os(iOS)
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif

    private func refreshSurface() {
        environment.toastCenter.show(message: "Agent surface refreshed.", style: .success)
    }

    private func closeSurface() {
        environment.closeWorkspacePane(workspacePane, source: "agent_surface_close")
    }

    private func copyMarkdownPayload() {
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

    private func shareSurfaceText() {
        guard let text = sharableTextPayload else { return }
        SystemSharePresenter.share(text: text)
    }

    private func downloadMarkdownPayload() {
        guard let markdown = markdownPayload else { return }
        exportFilename = exportMarkdownFilename
        exportDocument = MarkdownFileDocument(text: markdown)
        isExporting = true
    }

    private var markdownPayload: String? {
        if let markdown = surface.payload["markdown"]?.trimmedOrNil {
            return markdown
        }
        if let text = surface.payload["text"]?.trimmedOrNil {
            return text
        }
        return nil
    }

    private var sharableTextPayload: String? {
        if let markdown = markdownPayload {
            return markdown
        }
        if let summary = surface.payload["summary"]?.trimmedOrNil {
            return summary
        }
        return nil
    }

    private var exportMarkdownFilename: String {
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

private extension AgentWorkspaceSurfaceView {
    @ViewBuilder
    var surfaceActionsMenu: some View {
        #if os(macOS)
        Menu {
            sidebarMenuItemsView(contextMenuItems)
        } label: {
            HeaderActionIcon(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workspace options")
        .disabled(contextMenuItems.isEmpty)
        #else
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Workspace options",
            items: contextMenuItems,
            isCompact: true
        )
        .disabled(contextMenuItems.isEmpty)
        #endif
    }
}

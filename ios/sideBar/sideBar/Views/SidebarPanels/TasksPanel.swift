import SwiftUI

public struct TasksPanel: View {
    public init() {
    }

    public var body: some View {
        TasksPanelView()
    }
}

private struct TasksPanelView: View {
    @State private var searchQuery: String = ""
    @Environment(\.colorScheme) private var colorScheme
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            SidebarPanelPlaceholder(title: "Tasks")
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Tasks") {
                HStack(spacing: 30) {
                    Button {
                    } label: {
                        Image(systemName: "plus")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add task")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $searchQuery, placeholder: "Search tasks")
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}

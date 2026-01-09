import SwiftUI

public struct WorkspaceLayout<Main: View, Sidebar: View>: View {
    @Binding private var selection: AppSection?
    @Binding private var isLeftPanelExpanded: Bool
    @AppStorage(AppStorageKeys.sidebarWidth) private var leftPanelWidth: Double = 280
    @AppStorage(AppStorageKeys.rightSidebarWidth) private var rightSidebarWidth: Double = 360
    @State private var draggingLeftWidth: Double?
    @State private var draggingRightWidth: Double?

    private let railWidth: Double = 56
    private let dividerWidth: Double = 8
    private let minLeftPanelWidth: Double = 200
    private let maxLeftPanelWidth: Double = 500
    private let minRightSidebarWidth: Double = 280
    private let maxRightSidebarWidth: Double = 520
    private let minMainWidth: Double = 320

    private let mainContent: () -> Main
    private let rightSidebar: () -> Sidebar

    public init(
        selection: Binding<AppSection?>,
        isLeftPanelExpanded: Binding<Bool>,
        @ViewBuilder mainContent: @escaping () -> Main,
        @ViewBuilder rightSidebar: @escaping () -> Sidebar
    ) {
        self._selection = selection
        self._isLeftPanelExpanded = isLeftPanelExpanded
        self.mainContent = mainContent
        self.rightSidebar = rightSidebar
    }

    public var body: some View {
        GeometryReader { proxy in
            let widths = layoutWidths(for: proxy)
            HStack(spacing: 0) {
                SidebarRail(selection: $selection, onTogglePanel: toggleLeftPanel)
                    .frame(width: railWidth)

                if isLeftPanelExpanded {
                    panelView(for: selection)
                        .frame(width: widths.leftPanel)
                        .background(panelBackground)

                    resizeHandle(
                        width: dividerWidth,
                        onChanged: { delta in
                            let proposed = (draggingLeftWidth ?? leftPanelWidth) + delta
                            draggingLeftWidth = clampedLeftWidth(proposed, proxy: proxy)
                        },
                        onEnded: {
                            let proposed = draggingLeftWidth ?? leftPanelWidth
                            leftPanelWidth = clampedLeftWidth(proposed, proxy: proxy)
                            draggingLeftWidth = nil
                        }
                    )
                }

                mainContent()
                    .frame(width: widths.main)
                    .frame(maxHeight: .infinity)

                resizeHandle(
                    width: dividerWidth,
                    onChanged: { delta in
                        let proposed = (draggingRightWidth ?? rightSidebarWidth) - delta
                        draggingRightWidth = clampedRightWidth(proposed, proxy: proxy, leftPanelWidth: widths.leftPanel)
                    },
                    onEnded: {
                        let proposed = draggingRightWidth ?? rightSidebarWidth
                        rightSidebarWidth = clampedRightWidth(proposed, proxy: proxy, leftPanelWidth: widths.leftPanel)
                        draggingRightWidth = nil
                    }
                )

                rightSidebar()
                    .frame(width: widths.right)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func layoutWidths(for proxy: GeometryProxy) -> (leftPanel: Double, main: Double, right: Double) {
        let total = proxy.size.width
        let leftPanel = isLeftPanelExpanded ? clampedLeftWidth(draggingLeftWidth ?? leftPanelWidth, proxy: proxy) : 0
        let right = clampedRightWidth(draggingRightWidth ?? rightSidebarWidth, proxy: proxy, leftPanelWidth: leftPanel)
        let main = max(
            minMainWidth,
            total - railWidth - leftPanel - right - dividerWidth * (isLeftPanelExpanded ? 2 : 1)
        )
        return (leftPanel, main, right)
    }

    private func clampedLeftWidth(_ value: Double, proxy: GeometryProxy) -> Double {
        let maxAllowed = min(maxLeftPanelWidth, availableWidth(proxy: proxy) - minRightSidebarWidth - minMainWidth)
        return min(max(value, minLeftPanelWidth), maxAllowed)
    }

    private func clampedRightWidth(_ value: Double, proxy: GeometryProxy, leftPanelWidth: Double) -> Double {
        let maxAllowed = min(maxRightSidebarWidth, availableWidth(proxy: proxy) - leftPanelWidth - minMainWidth)
        return min(max(value, minRightSidebarWidth), maxAllowed)
    }

    private func availableWidth(proxy: GeometryProxy) -> Double {
        proxy.size.width - railWidth - dividerWidth * (isLeftPanelExpanded ? 2 : 1)
    }

    private func resizeHandle(width: Double, onChanged: @escaping (Double) -> Void, onEnded: @escaping () -> Void) -> some View {
        ZStack {
            Rectangle()
                .fill(handleBackground)
            Rectangle()
                .fill(handleBorder)
                .frame(width: 1)
                .offset(x: -(width / 2) + 0.5)
            Capsule()
                .fill(handleGrabber)
                .frame(width: 3, height: 28)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    onChanged(value.translation.width)
                }
                .onEnded { _ in
                    onEnded()
                }
        )
    }

    private func toggleLeftPanel() {
        isLeftPanelExpanded.toggle()
    }

    @ViewBuilder
    private func panelView(for selection: AppSection?) -> some View {
        switch selection {
        case .chat:
            ConversationsPanel()
        case .notes:
            NotesPanel()
        case .files:
            FilesPanel()
        case .websites:
            WebsitesPanel()
        case .none:
            SidebarPanelPlaceholder(title: "Select a section")
        default:
            SidebarPanelPlaceholder(title: selection?.title ?? "Select a section")
        }
    }

    private var panelBackground: Color {
        #if os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var handleBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    private var handleBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
    }

    private var handleGrabber: Color {
        #if os(macOS)
        return Color(nsColor: .tertiaryLabelColor)
        #else
        return Color(uiColor: .tertiaryLabel)
        #endif
    }
}

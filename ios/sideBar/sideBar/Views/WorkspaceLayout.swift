import SwiftUI

public struct WorkspaceLayout<Header: View, Main: View, Sidebar: View>: View {
    @Binding private var selection: AppSection?
    @Binding private var isLeftPanelExpanded: Bool
    @AppStorage(AppStorageKeys.rightSidebarWidth) private var rightSidebarWidth: Double = 360
    @State private var draggingRightWidth: Double?

    private let railWidth: Double = 56
    private let dividerWidth: Double = 8
    private let leftPanelWidth: Double = 280
    private let minRightSidebarWidth: Double = 280
    private let maxRightSidebarWidth: Double = 520
    private let minMainWidth: Double = 320

    private let header: () -> Header
    private let mainContent: () -> Main
    private let rightSidebar: () -> Sidebar

    public init(
        selection: Binding<AppSection?>,
        isLeftPanelExpanded: Binding<Bool>,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder mainContent: @escaping () -> Main,
        @ViewBuilder rightSidebar: @escaping () -> Sidebar
    ) {
        self._selection = selection
        self._isLeftPanelExpanded = isLeftPanelExpanded
        self.header = header
        self.mainContent = mainContent
        self.rightSidebar = rightSidebar
    }

    public var body: some View {
        GeometryReader { proxy in
            let widths = layoutWidths(for: proxy)
            HStack(spacing: 0) {
                SidebarRail(selection: $selection, onTogglePanel: toggleLeftPanel)
                    .frame(width: railWidth)

                Divider()

                if isLeftPanelExpanded {
                    panelView(for: selection)
                        .frame(width: widths.leftPanel)
                        .background(panelBackground)
                }

                VStack(spacing: 0) {
                    header()
                    Divider()
                    HStack(spacing: 0) {
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
        }
    }

    private func layoutWidths(for proxy: GeometryProxy) -> (leftPanel: Double, main: Double, right: Double) {
        let total = proxy.size.width
        let leftPanel = isLeftPanelExpanded ? leftPanelWidth : 0
        let right = clampedRightWidth(draggingRightWidth ?? rightSidebarWidth, proxy: proxy, leftPanelWidth: leftPanel)
        let main = max(
            minMainWidth,
            total - railWidth - leftPanel - right - dividerWidth
        )
        return (leftPanel, main, right)
    }

    private func clampedRightWidth(_ value: Double, proxy: GeometryProxy, leftPanelWidth: Double) -> Double {
        let maxAllowed = min(maxRightSidebarWidth, availableWidth(proxy: proxy) - leftPanelWidth - minMainWidth)
        return min(max(value, minRightSidebarWidth), maxAllowed)
    }

    private func availableWidth(proxy: GeometryProxy) -> Double {
        proxy.size.width - railWidth - dividerWidth
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

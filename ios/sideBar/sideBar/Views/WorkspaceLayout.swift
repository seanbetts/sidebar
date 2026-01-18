import SwiftUI

public struct WorkspaceLayout<Header: View, Main: View, Sidebar: View>: View {
    @Binding private var selection: AppSection?
    @Binding private var isLeftPanelExpanded: Bool
    private let onShowSettings: (() -> Void)?
    @AppStorage(AppStorageKeys.rightSidebarWidth) private var rightSidebarWidth: Double = 360
    @State private var draggingRightWidth: Double?

    private let defaultRightSidebarWidth: Double = 360
    private let railWidth: Double = 56
    private let dividerWidth: Double = 8
    private let leftPanelWidth: Double = 280
    private let minRightSidebarWidth: Double = 280
    private let minMainWidth: Double = 320

    private let header: () -> Header
    private let mainContent: () -> Main
    private let rightSidebar: () -> Sidebar

    public init(
        selection: Binding<AppSection?>,
        isLeftPanelExpanded: Binding<Bool>,
        onShowSettings: (() -> Void)? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder mainContent: @escaping () -> Main,
        @ViewBuilder rightSidebar: @escaping () -> Sidebar
    ) {
        self._selection = selection
        self._isLeftPanelExpanded = isLeftPanelExpanded
        self.onShowSettings = onShowSettings
        self.header = header
        self.mainContent = mainContent
        self.rightSidebar = rightSidebar
    }

    public var body: some View {
        GeometryReader { proxy in
            let widths = layoutWidths(for: proxy)
            HStack(alignment: .top, spacing: 0) {
                SidebarRail(
                    selection: $selection,
                    onTogglePanel: toggleLeftPanel,
                    onShowSettings: onShowSettings,
                    onSelectSection: { section in
                        if isLeftPanelExpanded && selection == section {
                            toggleLeftPanel()
                            return
                        }
                        if !isLeftPanelExpanded {
                            toggleLeftPanel()
                        }
                        selection = section
                    }
                )
                    .frame(width: railWidth)
                    .frame(maxHeight: .infinity)

                Divider()
                    .frame(maxHeight: .infinity)

                if isLeftPanelExpanded {
                    panelView(for: selection)
                        .frame(width: widths.leftPanel)
                        .frame(maxHeight: .infinity)
                        .background(panelBackground)
                        .transition(.opacity)
                        .clipped()
                        .zIndex(-1)
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
                                let clamped = clampedRightWidth(proposed, proxy: proxy, leftPanelWidth: widths.leftPanel)
                                #if os(macOS)
                                rightSidebarWidth = snappedRightWidth(clamped, proxy: proxy, leftPanelWidth: widths.leftPanel)
                                #else
                                rightSidebarWidth = clamped
                                #endif
                                draggingRightWidth = nil
                            },
                            onDoubleTap: {
                                toggleRightSidebarWidth(proxy: proxy, leftPanelWidth: widths.leftPanel)
                            }
                        )

                        rightSidebar()
                            .frame(width: widths.right)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.smooth(duration: 0.3), value: isLeftPanelExpanded)
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
        let maxAllowed = maxRightWidth(proxy: proxy, leftPanelWidth: leftPanelWidth)
        return min(max(value, minRightSidebarWidth), maxAllowed)
    }

    private func snappedRightWidth(_ value: Double, proxy: GeometryProxy, leftPanelWidth: Double) -> Double {
        let half = halfWidth(proxy: proxy, leftPanelWidth: leftPanelWidth)
        let maxAllowed = maxRightWidth(proxy: proxy, leftPanelWidth: leftPanelWidth)
        let snapPoints = [
            defaultRightSidebarWidth,
            420,
            480,
            maxAllowed,
            half
        ]
        let candidates = snapPoints
            .filter { $0 >= minRightSidebarWidth && $0 <= maxAllowed }
        let nearest = candidates.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
        return clampedRightWidth(nearest, proxy: proxy, leftPanelWidth: leftPanelWidth)
    }

    private func toggleRightSidebarWidth(proxy: GeometryProxy, leftPanelWidth: Double) {
        let half = halfWidth(proxy: proxy, leftPanelWidth: leftPanelWidth)
        let target: Double
        if abs(rightSidebarWidth - half) <= 8 {
            target = defaultRightSidebarWidth
        } else {
            target = half
        }
        rightSidebarWidth = clampedRightWidth(target, proxy: proxy, leftPanelWidth: leftPanelWidth)
    }

    private func halfWidth(proxy: GeometryProxy, leftPanelWidth: Double) -> Double {
        let available = availableWidth(proxy: proxy) - leftPanelWidth
        return max(minRightSidebarWidth, min(available * 0.5, maxRightWidth(proxy: proxy, leftPanelWidth: leftPanelWidth)))
    }

    private func maxRightWidth(proxy: GeometryProxy, leftPanelWidth: Double) -> Double {
        let usableWidth = availableWidth(proxy: proxy) - leftPanelWidth
        let half = usableWidth * 0.5
        let maxAllowed = usableWidth - minMainWidth
        #if os(macOS)
        return min(half, maxAllowed)
        #else
        return min(half, maxAllowed)
        #endif
    }

    private func availableWidth(proxy: GeometryProxy) -> Double {
        proxy.size.width - railWidth - dividerWidth
    }

    private func resizeHandle(
        width: Double,
        onChanged: @escaping (Double) -> Void,
        onEnded: @escaping () -> Void,
        onDoubleTap: (() -> Void)? = nil
    ) -> some View {
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
        .onTapGesture(count: 2) {
            onDoubleTap?()
        }
    }

    private func toggleLeftPanel() {
        let willExpand = !isLeftPanelExpanded
        isLeftPanelExpanded.toggle()
        if willExpand, selection == nil {
            selection = .notes
        }
    }

    @ViewBuilder
    private func panelView(for selection: AppSection?) -> some View {
        switch selection {
        case .chat:
            ConversationsPanel()
        case .notes:
            NotesPanel()
        case .tasks:
            TasksPanel()
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
        DesignTokens.Colors.sidebar
    }

    private var handleBackground: Color {
        DesignTokens.Colors.background
    }

    private var handleBorder: Color {
        DesignTokens.Colors.border
    }

    private var handleGrabber: Color {
        DesignTokens.Colors.textTertiary
    }
}

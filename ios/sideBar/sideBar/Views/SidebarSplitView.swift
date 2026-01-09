import SwiftUI

public struct SidebarSplitView<Detail: View>: View {
    @Binding private var selection: AppSection?
    @AppStorage(AppStorageKeys.sidebarWidth) private var sidebarWidth: Double = 280
    @State private var dragWidth: Double?

    private let detail: () -> Detail

    private let railWidth: Double = 56
    private let dividerWidth: Double = 8
    private let minPanelWidth: Double = 200
    private let maxPanelWidth: Double = 500

    public init(selection: Binding<AppSection?>, @ViewBuilder detail: @escaping () -> Detail) {
        self._selection = selection
        self.detail = detail
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                SidebarRail(selection: $selection)
                    .frame(width: railWidth)

                SidebarPanelPlaceholder(title: selection?.title ?? "Select a section")
                    .frame(width: currentPanelWidth(for: proxy))
                    .background(panelBackground)

                resizeHandle(for: proxy)

                detail()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func resizeHandle(for proxy: GeometryProxy) -> some View {
        ZStack {
            Rectangle()
                .fill(handleBackground)
            Rectangle()
                .fill(handleBorder)
                .frame(width: 1)
                .offset(x: -(dividerWidth / 2) + 0.5)
            Capsule()
                .fill(handleGrabber)
                .frame(width: 3, height: 28)
        }
        .frame(width: dividerWidth)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let proposed = (dragWidth ?? sidebarWidth) + value.translation.width
                    dragWidth = clampedWidth(proposed, proxy: proxy)
                }
                .onEnded { _ in
                    let proposed = dragWidth ?? sidebarWidth
                    sidebarWidth = snappedWidth(proposed, proxy: proxy)
                    dragWidth = nil
                }
        )
    }

    private func currentPanelWidth(for proxy: GeometryProxy) -> Double {
        clampedWidth(dragWidth ?? sidebarWidth, proxy: proxy)
    }

    private func clampedWidth(_ value: Double, proxy: GeometryProxy) -> Double {
        let maxWidth = min(maxPanelWidth, availableWidth(for: proxy))
        return min(max(value, minPanelWidth), maxWidth)
    }

    private func snappedWidth(_ value: Double, proxy: GeometryProxy) -> Double {
        let candidates = snapPoints(for: proxy)
        guard let closest = candidates.min(by: { abs($0 - value) < abs($1 - value) }) else {
            return clampedWidth(value, proxy: proxy)
        }
        let snapped = abs(closest - value) <= 24 ? closest : value
        return clampedWidth(snapped, proxy: proxy)
    }

    private func snapPoints(for proxy: GeometryProxy) -> [Double] {
        let available = availableWidth(for: proxy)
        let points = [available * 0.33, available * 0.4, available * 0.5]
        return points.map { clampedWidth($0, proxy: proxy) }
    }

    private func availableWidth(for proxy: GeometryProxy) -> Double {
        max(0, proxy.size.width - railWidth - dividerWidth)
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

import SwiftUI

public struct SidebarSplitView<Detail: View>: View {
    @Binding private var selection: AppSection?
    @AppStorage(AppStorageKeys.sidebarWidth) private var sidebarWidth: Double = 280

    private let panelContent: (AppSection?) -> AnyView
    private let detail: () -> Detail

    private let railWidth: Double = Double(DesignTokens.Size.railWidth)
    private let dividerWidth: Double = Double(DesignTokens.Size.dividerWidth)

    public init(
        selection: Binding<AppSection?>,
        panelContent: @escaping (AppSection?) -> AnyView = { _ in
            AnyView(SidebarPanelPlaceholder(title: "Select a section"))
        },
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self._selection = selection
        self.panelContent = panelContent
        self.detail = detail
    }

    public var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                SidebarRail(selection: $selection)
                    .frame(width: railWidth)

                panelView(for: selection)
                    .frame(width: sidebarWidth)
                    .background(panelBackground)

                divider

                detail()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var divider: some View {
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
    }

    private var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    @ViewBuilder
    private func panelView(for selection: AppSection?) -> some View {
        panelContent(selection)
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

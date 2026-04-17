import SwiftUI

struct PanelHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let minimumContentHeight: CGFloat?
    let trailing: Trailing
    @EnvironmentObject private var environment: AppEnvironment
#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    init(
        title: String,
        subtitle: String? = nil,
        minimumContentHeight: CGFloat? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.minimumContentHeight = minimumContentHeight
        self.trailing = trailing()
    }

    init(
        title: String,
        subtitle: String? = nil,
        minimumContentHeight: CGFloat? = nil
    ) where Trailing == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.minimumContentHeight = minimumContentHeight
        self.trailing = EmptyView()
    }

    var body: some View {
        Group {
            if let chrome = Self.chrome(
                isMacOS: Self.runsOnMacOS,
                colorScheme: colorScheme
            ) {
                headerContent
                    .glassChrome(chrome)
            } else {
                headerContent
            }
        }
        .overlay(alignment: .bottom) {
            EmptyView()
        }
    }

    private var headerContent: some View {
        let content = HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            Spacer()
            if shouldShowOfflineBanner {
                OfflineBanner()
            }
            trailing
        }

        if let minimumContentHeight {
            return AnyView(
                content
                    .frame(minHeight: minimumContentHeight, alignment: .center)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
            )
        }

        return AnyView(
            content
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
        )
    }

    @Environment(\.colorScheme) private var colorScheme

    static func chrome(isMacOS: Bool, colorScheme: ColorScheme) -> GlassChrome.Kind? {
        _ = isMacOS
        _ = colorScheme
        return nil
    }

    private static var runsOnMacOS: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    private var shouldShowOfflineBanner: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
            && (environment.isOffline || environment.writeQueue.isProcessing || environment.writeQueue.pendingCount > 0)
        #endif
    }
}

import SwiftUI

struct PanelHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var environment: AppEnvironment
#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    init(title: String, subtitle: String? = nil) where Trailing == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            Spacer()
            if shouldShowOfflineBanner {
                OfflineBanner()
            }
            trailing
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            EmptyView()
        }
    }

    private var headerBackground: Color {
        #if os(macOS)
        if colorScheme == .light {
            return DesignTokens.Colors.sidebar
        }
        return DesignTokens.Colors.surface
        #else
        return DesignTokens.Colors.surface
        #endif
    }

    private var shouldShowOfflineBanner: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact && !environment.isNetworkAvailable
        #endif
    }
}

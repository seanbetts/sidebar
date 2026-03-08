import SwiftUI

struct PanelHeader<Trailing: View>: View {
    enum BackgroundStyle: Equatable {
        case sidebar
        case surface

        var color: Color {
            switch self {
            case .sidebar:
                return DesignTokens.Colors.sidebar
            case .surface:
                return DesignTokens.Colors.surface
            }
        }
    }

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
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            EmptyView()
        }
    }

    private var headerBackground: Color {
        Self.backgroundStyle(
            isMacOS: Self.runsOnMacOS,
            colorScheme: colorScheme
        ).color
    }

    static func backgroundStyle(isMacOS: Bool, colorScheme: ColorScheme) -> BackgroundStyle {
        if isMacOS {
            return colorScheme == .light ? .sidebar : .surface
        }
        return .sidebar
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

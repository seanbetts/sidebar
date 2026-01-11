import SwiftUI

struct PanelHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing
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
            trailing
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            EmptyView()
        }
    }

    private var backgroundColor: Color {
        #if os(macOS)
        return DesignTokens.Colors.background
        #else
        return horizontalSizeClass == .compact ? DesignTokens.Colors.background : DesignTokens.Colors.surface
        #endif
    }
}

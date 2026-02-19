import SwiftUI

struct PhoneFloatingActionDock<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            content
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

struct PhoneFloatingActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DesignTokens.Typography.labelMd)
                .frame(width: DesignTokens.Size.touchTarget, height: DesignTokens.Size.touchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct PhoneFloatingActionDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignTokens.Colors.border)
            .frame(width: 1, height: 16)
    }
}

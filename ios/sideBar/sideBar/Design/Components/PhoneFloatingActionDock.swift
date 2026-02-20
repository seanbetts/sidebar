import SwiftUI

enum PhoneFloatingActionMetrics {
    static let buttonSize: CGFloat = 40
}

struct PhoneFloatingActionDock<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            content
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .frame(width: PhoneFloatingActionMetrics.buttonSize, height: PhoneFloatingActionMetrics.buttonSize)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct PhoneFloatingActionDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignTokens.Colors.border)
            .frame(width: 1, height: 12)
    }
}

import SwiftUI

struct HeaderActionIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(DesignTokens.Typography.labelMd)
            .frame(width: 28, height: 20)
            .imageScale(.medium)
    }
}

struct HeaderActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            HeaderActionIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
    }
}

struct HeaderActionRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}

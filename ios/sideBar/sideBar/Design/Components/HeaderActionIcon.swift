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

#if os(iOS)
struct HeaderActionMenuButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let items: [SidebarMenuItem]
    let isCompact: Bool

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            let menuSignature = items
                .map { "\($0.title)|\($0.systemImage ?? "")|\(roleSignature($0.role))" }
                .joined(separator: ";")
            UIKitMenuButton(
                systemImage: systemImage,
                accessibilityLabel: accessibilityLabel,
                items: items
            )
            .frame(width: 28, height: isCompact ? 20 : 28)
            .fixedSize()
            .accessibilityLabel(accessibilityLabel)
            .id(menuSignature)
        } else {
            Menu {
                sidebarMenuItemsView(items)
            } label: {
                HeaderActionIcon(systemName: systemImage)
                    .frame(width: 28, height: isCompact ? 20 : 28)
            }
            .buttonStyle(.plain)
            .menuStyle(.button)
            .accessibilityLabel(accessibilityLabel)
            .fixedSize()
        }
    }

    private func roleSignature(_ role: ButtonRole?) -> String {
        switch role {
        case .destructive:
            return "destructive"
        case .cancel:
            return "cancel"
        default:
            return "default"
        }
    }
}
#endif

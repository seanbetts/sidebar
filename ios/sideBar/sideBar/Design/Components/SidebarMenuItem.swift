import SwiftUI

struct SidebarMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let handler: () -> Void
}

@ViewBuilder
func sidebarMenuItemsView(_ items: [SidebarMenuItem]) -> some View {
    ForEach(items) { item in
        Button(role: item.role) {
            item.handler()
        } label: {
            if let systemImage = item.systemImage {
                Label(item.title, systemImage: systemImage)
            } else {
                Text(item.title)
            }
        }
        .foregroundStyle(item.role == .destructive ? DesignTokens.Colors.error : DesignTokens.Colors.textPrimary)
    }
}

import SwiftUI

struct SidebarMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let handler: () -> Void
}

enum SidebarMenuItemTintPolicy: Equatable {
    case sidebarText
    case systemRole
}

func sidebarMenuItemTintPolicy(for item: SidebarMenuItem) -> SidebarMenuItemTintPolicy {
    item.role == .destructive ? .systemRole : .sidebarText
}

extension SidebarMenuItem {
    static func pin(isPinned: Bool, handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(
            title: isPinned ? "Unpin" : "Pin",
            systemImage: isPinned ? "pin.slash" : "pin",
            role: nil,
            handler: handler
        )
    }

    static func archive(isArchived: Bool, handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(
            title: isArchived ? "Unarchive" : "Archive",
            systemImage: isArchived ? "archivebox.fill" : "archivebox",
            role: nil,
            handler: handler
        )
    }

    static func rename(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Rename", systemImage: "pencil", role: nil, handler: handler)
    }

    static func move(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Move", systemImage: "arrow.forward.folder", role: nil, handler: handler)
    }

    static func copy(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy", systemImage: "doc.on.doc", role: nil, handler: handler)
    }

    static func copyTranscript(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy Transcript", systemImage: "doc.on.doc", role: nil, handler: handler)
    }

    static func copyText(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy Text", systemImage: "doc.on.doc", role: nil, handler: handler)
    }

    static func copyMarkdown(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy Markdown", systemImage: "doc.on.doc", role: nil, handler: handler)
    }

    static func download(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Download", systemImage: "square.and.arrow.down", role: nil, handler: handler)
    }

    static func share(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Share URL", systemImage: "square.and.arrow.up.on.square", role: nil, handler: handler)
    }

    static func shareText(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(
            title: "Share Text",
            systemImage: "square.and.arrow.up.on.square",
            role: nil,
            handler: handler
        )
    }

    static func delete(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Delete", systemImage: "trash", role: .destructive, handler: handler)
    }
}

@ViewBuilder
func sidebarMenuItemsView(_ items: [SidebarMenuItem]) -> some View {
    ForEach(items) { item in
        switch sidebarMenuItemTintPolicy(for: item) {
        case .sidebarText:
            Button(role: item.role) {
                item.handler()
            } label: {
                if let systemImage = item.systemImage {
                    Label(item.title, systemImage: systemImage)
                } else {
                    Text(item.title)
                }
            }
            .foregroundStyle(DesignTokens.Colors.textPrimary)
        case .systemRole:
            Button(role: item.role) {
                item.handler()
            } label: {
                if let systemImage = item.systemImage {
                    Label(item.title, systemImage: systemImage)
                } else {
                    Text(item.title)
                }
            }
        }
    }
}

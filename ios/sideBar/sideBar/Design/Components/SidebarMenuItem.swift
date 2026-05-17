import SwiftUI
import sideBarShared

struct SidebarMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: AppIcon?
    let role: ButtonRole?
    let handler: () -> Void

    init(title: String, icon: AppIcon?, role: ButtonRole?, handler: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.role = role
        self.handler = handler
    }
}

enum SidebarMenuItemTintPolicy: Equatable {
    case sidebarText
}

func sidebarMenuItemTintPolicy(for item: SidebarMenuItem) -> SidebarMenuItemTintPolicy {
    .sidebarText
}

extension SidebarMenuItem {
    static func pin(isPinned: Bool, handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(
            title: isPinned ? "Unpin" : "Pin",
            icon: isPinned ? AppIcon.Action.unpin : AppIcon.Action.pin,
            role: nil,
            handler: handler
        )
    }

    static func archive(isArchived: Bool, handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(
            title: isArchived ? "Unarchive" : "Archive",
            icon: isArchived ? AppIcon.Action.unarchive : AppIcon.Action.archive,
            role: nil,
            handler: handler
        )
    }

    static func rename(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Rename", icon: AppIcon.Action.rename, role: nil, handler: handler)
    }

    static func move(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Move", icon: AppIcon.Action.move, role: nil, handler: handler)
    }

    static func reorder(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Reorder", icon: AppIcon.Action.reorder, role: nil, handler: handler)
    }

    static func copy(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy", icon: AppIcon.Action.copy, role: nil, handler: handler)
    }

    static func copyTranscript(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy Transcript", icon: AppIcon.Action.copy, role: nil, handler: handler)
    }

    static func shareTranscript(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Share Transcript", icon: AppIcon.Action.share, role: nil, handler: handler)
    }

    static func exportTranscript(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Export Transcript", icon: AppIcon.Action.download, role: nil, handler: handler)
    }

    static func copyText(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy Text", icon: AppIcon.Action.copy, role: nil, handler: handler)
    }

    static func copyMarkdown(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy Markdown", icon: AppIcon.Action.copy, role: nil, handler: handler)
    }

    static func copyTitle(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy Title", icon: AppIcon.Action.copyTitle, role: nil, handler: handler)
    }

    static func copyURL(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Copy URL", icon: AppIcon.Action.copyURL, role: nil, handler: handler)
    }

    static func download(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Download", icon: AppIcon.Action.download, role: nil, handler: handler)
    }

    static func share(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Share URL", icon: AppIcon.Action.shareOnSquare, role: nil, handler: handler)
    }

    static func shareFile(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Share", icon: AppIcon.Action.share, role: nil, handler: handler)
    }

    static func shareText(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(
            title: "Share Text",
            icon: AppIcon.Action.shareOnSquare,
            role: nil,
            handler: handler
        )
    }

    static func delete(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Delete", icon: AppIcon.Action.delete, role: .destructive, handler: handler)
    }

    static func newTask(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "New task", icon: AppIcon.State.successCircle, role: nil, handler: handler)
    }

    static func newGroup(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "New group", icon: AppIcon.Content.folder, role: nil, handler: handler)
    }

    static func newProject(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "New project", icon: AppIcon.Content.taskList, role: nil, handler: handler)
    }

    static func refresh(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Refresh", icon: AppIcon.Action.refresh, role: nil, handler: handler)
    }

    static func close(handler: @escaping () -> Void) -> SidebarMenuItem {
        SidebarMenuItem(title: "Close", icon: AppIcon.Action.close, role: nil, handler: handler)
    }
}

@ViewBuilder
func sidebarMenuItemsView(_ items: [SidebarMenuItem]) -> some View {
    ForEach(items) { item in
        Button(role: item.role) {
            item.handler()
        } label: {
            if let icon = item.icon {
                Label(item.title, systemImage: icon.rawValue)
            } else {
                Text(item.title)
            }
        }
    }
}

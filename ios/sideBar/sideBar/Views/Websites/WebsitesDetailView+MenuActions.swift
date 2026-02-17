import SwiftUI

extension WebsitesDetailView {
    var websiteActionsMenu: some View {
        #if os(macOS)
        Menu {
            Button {
                guard let websiteId = viewModel.active?.id else { return }
                Task {
                    await viewModel.setPinned(id: websiteId, pinned: !isPinned)
                }
            } label: {
                Label(pinActionTitle, systemImage: pinIconName)
            }
            Button {
                renameValue = viewModel.active?.title ?? ""
                isRenameDialogPresented = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                copyWebsiteContent()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                copyWebsiteTitle()
            } label: {
                Label("Copy Title", systemImage: "textformat")
            }
            Button {
                copyWebsiteURL()
            } label: {
                Label("Copy URL", systemImage: "link")
            }
            Button {
                shareWebsiteURL()
            } label: {
                Label("Share URL", systemImage: "square.and.arrow.up")
            }
            Button {
                shareWebsiteText()
            } label: {
                Label("Share Text", systemImage: "square.and.arrow.up.on.square")
            }
            Button {
                exportWebsite()
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
            Button {
                archiveActiveWebsite()
            } label: {
                Label(archiveMenuTitle, systemImage: archiveIconName)
            }
            Button(role: .destructive) {
                isDeleteAlertPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            HeaderActionIcon(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Website options")
        .disabled(viewModel.active == nil)
        #else
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Website options",
            items: websiteHeaderMenuItems,
            isCompact: isCompact
        )
        .disabled(viewModel.active == nil)
        #endif
    }

    #if os(iOS)
    var websiteToolbarMenu: some View {
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Website options",
            items: websiteHeaderMenuItems,
            isCompact: isCompact
        )
        .disabled(viewModel.active == nil)
    }
    #endif

    private var websiteHeaderMenuItems: [SidebarMenuItem] {
        [
            .pin(isPinned: isPinned) {
                guard let websiteId = viewModel.active?.id else { return }
                Task {
                    await viewModel.setPinned(id: websiteId, pinned: !isPinned)
                }
            },
            .rename {
                renameValue = viewModel.active?.title ?? ""
                isRenameDialogPresented = true
            },
            .copy {
                copyWebsiteContent()
            },
            SidebarMenuItem(title: "Copy Title", systemImage: "textformat", role: nil) {
                copyWebsiteTitle()
            },
            SidebarMenuItem(title: "Copy URL", systemImage: "link", role: nil) {
                copyWebsiteURL()
            },
            .share {
                shareWebsiteURL()
            },
            .shareText {
                shareWebsiteText()
            },
            .download {
                exportWebsite()
            },
            .archive(isArchived: isArchived) {
                archiveActiveWebsite()
            },
            .delete {
                isDeleteAlertPresented = true
            }
        ]
    }
}

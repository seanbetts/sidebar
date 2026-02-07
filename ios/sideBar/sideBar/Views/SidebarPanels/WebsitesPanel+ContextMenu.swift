import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension WebsitesPanelView {
    @ViewBuilder
    func websiteContextMenuItems(for item: WebsiteItem) -> some View {
        sidebarMenuItemsView(websiteContextMenuItemsList(for: item))
    }

    func websiteContextMenuItemsList(for item: WebsiteItem) -> [SidebarMenuItem] {
        [
            SidebarMenuItem(title: websitePinTitle(for: item), systemImage: websitePinIconName(for: item), role: nil) {
                Task { await viewModel.setPinned(id: item.id, pinned: !item.pinned) }
            },
            SidebarMenuItem(title: "Rename", systemImage: "pencil", role: nil) {
                beginRename(for: item)
            },
            SidebarMenuItem(title: "Copy", systemImage: "doc.on.doc", role: nil) {
                Task { await copyWebsiteContent(for: item) }
            },
            SidebarMenuItem(title: "Copy Title", systemImage: "textformat", role: nil) {
                copyWebsiteTitle(for: item)
            },
            SidebarMenuItem(title: "Copy URL", systemImage: "link", role: nil) {
                copyWebsiteURL(for: item)
            },
            SidebarMenuItem(title: "Download", systemImage: "square.and.arrow.down", role: nil) {
                Task { await exportWebsiteContent(for: item) }
            },
            SidebarMenuItem(title: websiteArchiveTitle(for: item), systemImage: websiteArchiveIconName(for: item), role: nil) {
                Task { await viewModel.setArchived(id: item.id, archived: !item.archived) }
            },
            SidebarMenuItem(title: "Delete", systemImage: "trash", role: .destructive) {
                deleteTarget = item
            }
        ]
    }

    private func websitePinTitle(for item: WebsiteItem) -> String {
        item.pinned ? "Unpin" : "Pin"
    }

    private func websitePinIconName(for item: WebsiteItem) -> String {
        item.pinned ? "pin.slash" : "pin"
    }

    private func websiteArchiveTitle(for item: WebsiteItem) -> String {
        item.archived ? "Unarchive" : "Archive"
    }

    private func websiteArchiveIconName(for item: WebsiteItem) -> String {
        item.archived ? "archivebox.fill" : "archivebox"
    }

    @MainActor
    private func ensureWebsiteLoaded(_ item: WebsiteItem) async {
        await viewModel.loadById(id: item.id)
    }

    private func beginRename(for item: WebsiteItem) {
        renameTarget = item
        renameValue = item.title.isEmpty ? item.url : item.title
        isRenameDialogPresented = true
    }

    func commitRename() {
        guard let target = renameTarget else { return }
        let updatedName = renameValue
        renameTarget = nil
        renameValue = ""
        Task {
            await viewModel.renameWebsite(id: target.id, title: updatedName)
        }
        isRenameDialogPresented = false
    }

    @MainActor
    private func copyWebsiteContent(for item: WebsiteItem) async {
        await ensureWebsiteLoaded(item)
        guard let content = viewModel.active?.content, !content.isEmpty else {
            self.appEnvironment.toastCenter.show(message: "Copy unavailable")
            return
        }
        let stripped = MarkdownRendering.stripFrontmatter(content)
        guard !stripped.isEmpty else {
            self.appEnvironment.toastCenter.show(message: "Copy unavailable")
            return
        }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = stripped
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(stripped, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == stripped {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == stripped {
                pasteboard.string = ""
            }
            #endif
        }
    }

    @MainActor
    private func exportWebsiteContent(for item: WebsiteItem) async {
        await ensureWebsiteLoaded(item)
        guard let website = viewModel.active else {
            self.appEnvironment.toastCenter.show(message: "Download unavailable")
            return
        }
        let fallbackName = website.title.isEmpty ? "website" : website.title
        let stripped = MarkdownRendering.stripFrontmatter(website.content)
        guard !stripped.isEmpty else {
            self.appEnvironment.toastCenter.show(message: "Download unavailable")
            return
        }
        exportFilename = "\(fallbackName).md"
        exportDocument = MarkdownFileDocument(text: stripped)
        isExporting = true
    }

    private func copyWebsiteURL(for item: WebsiteItem) {
        let urlString = item.url
        guard !urlString.isEmpty else {
            self.appEnvironment.toastCenter.show(message: "Copy unavailable")
            return
        }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = urlString
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == urlString {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == urlString {
                pasteboard.string = ""
            }
            #endif
        }
    }

    private func copyWebsiteTitle(for item: WebsiteItem) {
        let title = item.title.isEmpty ? item.url : item.title
        guard !title.isEmpty else {
            self.appEnvironment.toastCenter.show(message: "Copy unavailable")
            return
        }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = title
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(title, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == title {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == title {
                pasteboard.string = ""
            }
            #endif
        }
    }
}

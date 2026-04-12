import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension NotesPanelView {
    enum NoteContextMenuAction: Equatable {
        case pin
        case rename
        case move
        case copyText
        case shareText
        case download
        case archive
        case delete
    }

    var moveFolderOptions: [FolderOption] {
        FolderOption.build(from: viewModel.tree?.children ?? [])
    }

    @ViewBuilder
    func noteContextMenuItems(for item: FileNodeItem) -> some View {
        sidebarMenuItemsView(noteContextMenuItemsList(for: item))
    }

    func noteContextMenuItemsList(for item: FileNodeItem) -> [SidebarMenuItem] {
        let items: [SidebarMenuItem] = noteContextMenuActions(for: item).map { action in
            switch action {
            case .pin:
                return SidebarMenuItem.pin(isPinned: item.pinned) {
                    togglePin(for: item)
                }
            case .rename:
                return SidebarMenuItem.rename {
                    beginRename(for: item)
                }
            case .move:
                return SidebarMenuItem.move {
                    beginMove(for: item)
                }
            case .copyText:
                return SidebarMenuItem.copyText {
                    Task { await copyNoteContent(for: item) }
                }
            case .shareText:
                return SidebarMenuItem.shareText {
                    Task { await shareNoteContent(for: item) }
                }
            case .download:
                return SidebarMenuItem.download {
                    Task { await exportNoteContent(for: item) }
                }
            case .archive:
                return SidebarMenuItem.archive(isArchived: item.archived) {
                    toggleArchive(for: item)
                }
            case .delete:
                return SidebarMenuItem.delete {
                    confirmDelete(for: item)
                }
            }
        }

        return items
    }

    static func noteContextMenuActions(for item: FileNodeItem) -> [NoteContextMenuAction] {
        if item.isFile {
            return [
                .pin,
                .rename,
                .move,
                .copyText,
                .shareText,
                .download,
                .archive,
                .delete
            ]
        }

        return [
            .rename,
            .delete
        ]
    }

    func noteContextMenuActions(for item: FileNodeItem) -> [NoteContextMenuAction] {
        Self.noteContextMenuActions(for: item)
    }

    private func beginMove(for item: FileNodeItem) {
        moveTargetId = item.id
        moveSelection = currentFolderPath(for: item)
        isMoveSheetPresented = true
    }

    private func currentFolderPath(for item: FileNodeItem) -> String {
        guard let lastSlash = item.id.lastIndex(of: "/") else { return "" }
        return String(item.id[..<lastSlash])
    }

    private func togglePin(for item: FileNodeItem) {
        Haptics.selection()
        Task {
            await viewModel.setPinned(id: item.id, pinned: !item.pinned)
        }
    }

    private func toggleArchive(for item: FileNodeItem) {
        Haptics.selection()
        Task {
            prepareForDestructiveAction()
            await waitForKeyboardDismissal()
            await viewModel.setArchived(id: item.id, archived: !item.archived)
        }
    }

    @MainActor
    private func copyNoteContent(for item: FileNodeItem) async {
        guard let content = await loadNoteContent(for: item) else { return }
        guard !content.isEmpty else {
            environment.toastCenter.show(message: "Copy unavailable")
            return
        }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = content
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == content {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == content {
                pasteboard.string = ""
            }
            #endif
        }
    }

    @MainActor
    private func exportNoteContent(for item: FileNodeItem) async {
        guard let content = await loadNoteContent(for: item) else { return }
        guard !content.isEmpty else {
            environment.toastCenter.show(message: "Download unavailable")
            return
        }
        exportFilename = item.name
        exportDocument = PlainTextFileDocument(text: content)
        isExporting = true
    }

    @MainActor
    private func shareNoteContent(for item: FileNodeItem) async {
        guard let content = await loadNoteContent(for: item), !content.isEmpty else {
            environment.toastCenter.show(message: "Share unavailable")
            return
        }
        SystemSharePresenter.share(text: content)
    }

    @MainActor
    private func loadNoteContent(for item: FileNodeItem) async -> String? {
        if viewModel.selectedNoteId != item.id {
            requestNoteSelection(id: item.id)
        }
        return await waitForNoteContent(id: item.id)
    }

    @MainActor
    private func waitForNoteContent(id: String, timeout: UInt64 = 2_000_000_000) async -> String? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout) / 1_000_000_000)
        while Date() < deadline {
            if viewModel.activeNote?.path == id {
                return viewModel.activeNote?.plainText
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }
}

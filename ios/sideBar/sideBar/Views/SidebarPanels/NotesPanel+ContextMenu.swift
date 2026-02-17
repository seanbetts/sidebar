import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension NotesPanelView {
    var moveFolderOptions: [FolderOption] {
        FolderOption.build(from: viewModel.tree?.children ?? [])
    }

    @ViewBuilder
    func noteContextMenuItems(for item: FileNodeItem) -> some View {
        sidebarMenuItemsView(noteContextMenuItemsList(for: item))
    }

    func noteContextMenuItemsList(for item: FileNodeItem) -> [SidebarMenuItem] {
        if item.isFile {
            return [
                .pin(isPinned: item.pinned) {
                    togglePin(for: item)
                },
                .rename {
                    beginRename(for: item)
                },
                .move {
                    beginMove(for: item)
                },
                .copy {
                    Task { await copyNoteContent(for: item) }
                },
                .shareText {
                    Task { await shareNoteContent(for: item) }
                },
                .download {
                    Task { await exportNoteContent(for: item) }
                },
                .archive(isArchived: item.archived) {
                    toggleArchive(for: item)
                },
                .delete {
                    confirmDelete(for: item)
                }
            ]
        }

        return [
            .rename {
                beginRename(for: item)
            },
            .delete {
                confirmDelete(for: item)
            }
        ]
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
        Task {
            await viewModel.setPinned(id: item.id, pinned: !item.pinned)
        }
    }

    private func toggleArchive(for item: FileNodeItem) {
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
        let filename = item.name.hasSuffix(".md") ? item.name : "\(item.name).md"
        exportFilename = filename
        exportDocument = MarkdownFileDocument(text: content)
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
                return viewModel.activeNote?.content
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }
}

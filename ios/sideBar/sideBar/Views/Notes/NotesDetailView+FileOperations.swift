import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension NotesDetailView {
    var activeNode: FileNode? {
        guard let noteId = viewModel.activeNote?.path else { return nil }
        return viewModel.noteNode(id: noteId)
    }

    var isPinned: Bool {
        activeNode?.pinned == true
    }

    var isArchived: Bool {
        activeNode?.archived == true
    }

    var pinActionTitle: String {
        isPinned ? "Unpin" : "Pin"
    }

    var pinIconName: String {
        isPinned ? "pin.slash" : "pin"
    }

    var archiveMenuTitle: String {
        isArchived ? "Unarchive" : "Archive"
    }

    var archiveIconName: String {
        isArchived ? "archivebox.fill" : "archivebox"
    }

    var currentFolderPath: String {
        guard let path = activeNode?.path else { return "" }
        guard let lastSlash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<lastSlash])
    }

    var folderOptions: [FolderOption] {
        FolderOption.build(from: viewModel.tree?.children ?? [])
    }

    func archiveActiveNote() {
        guard let noteId = viewModel.activeNote?.path else { return }
        Task {
            await viewModel.setArchived(id: noteId, archived: !isArchived)
        }
    }

    func copyMarkdown() {
        let text = editorViewModel.content.isEmpty ? viewModel.activeNote?.content ?? "" : editorViewModel.content
        guard !text.isEmpty else { return }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == text {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == text {
                pasteboard.string = ""
            }
            #endif
        }
    }

    func exportMarkdown() {
        let text = editorViewModel.content.isEmpty ? viewModel.activeNote?.content ?? "" : editorViewModel.content
        guard let name = viewModel.activeNote?.name else { return }
        let filename = name.hasSuffix(".md") ? name : "\(name).md"
        exportFilename = filename
        exportDocument = MarkdownFileDocument(text: text)
        isExporting = true
    }

    func requestCloseNote() {
        if editorViewModel.isDirty {
            isCloseConfirmPresented = true
            return
        }
        viewModel.clearSelection()
    }
}

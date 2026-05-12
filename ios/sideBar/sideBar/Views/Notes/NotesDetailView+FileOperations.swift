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

    var currentFolderPath: String {
        guard let path = activeNode?.path else { return "" }
        guard let lastSlash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<lastSlash])
    }

    var folderOptions: [FolderOption] {
        FolderOption.build(from: viewModel.tree?.children ?? [])
    }

    func togglePinnedForActiveNote() {
        guard let noteId = viewModel.activeNote?.path else { return }
        Haptics.selection()
        Task {
            await viewModel.setPinned(id: noteId, pinned: !isPinned)
        }
    }

    func archiveActiveNote() {
        guard let noteId = viewModel.activeNote?.path else { return }
        Haptics.selection()
        Task {
            await viewModel.setArchived(id: noteId, archived: !isArchived)
        }
    }

    func copyNoteText() {
        let text = editorViewModel.currentPlainTextSnapshot()
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

    func exportNoteText() {
        let text = editorViewModel.currentPlainTextSnapshot()
        guard let name = viewModel.activeNote?.name else { return }
        exportFilename = name
        exportDocument = PlainTextFileDocument(text: text)
        isExporting = true
    }

    func shareNoteText() {
        let text = editorViewModel.currentPlainTextSnapshot()
        guard !text.isEmpty else { return }
        SystemSharePresenter.share(text: text, anchorID: SystemShareAnchorID.notesHeaderActionsMenu)
    }

}

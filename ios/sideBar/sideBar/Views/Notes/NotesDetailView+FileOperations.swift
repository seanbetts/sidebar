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
        SystemSharePresenter.share(text: text)
    }

    func requestCloseNote() {
        if editorViewModel.isDirty {
            isCloseConfirmPresented = true
            return
        }
        viewModel.clearSelection()
    }

    func copyCorruptPlainText(_ note: NotePayload) {
        guard !note.content.isEmpty else {
            environment.toastCenter.show(message: "No plain text is available for this note.")
            return
        }
        copyToPasteboard(note.content)
        environment.toastCenter.show(message: "Plain text copied.", style: .success)
    }

    func restoreCorruptNoteFromLegacy(_ note: NotePayload) async {
        guard let legacyContent = note.legacyContent, !legacyContent.isEmpty else {
            environment.toastCenter.show(message: "No legacy content is available to restore.")
            return
        }
        let restored = await viewModel.updateNoteContent(id: note.id, content: legacyContent)
        if restored {
            environment.toastCenter.show(message: "Restored note from legacy content.", style: .success)
        } else {
            environment.toastCenter.show(message: "Failed to restore note from legacy content.")
        }
    }

    func copyCorruptionReport(_ note: NotePayload) {
        let contentFormat = note.contentFormat ?? "unknown"
        let hasLegacyContent = !(note.legacyContent ?? "").isEmpty
        let report = """
        {
          "id":"\(note.id)",
          "path":"\(note.path)",
          "content_format":"\(contentFormat)",
          "is_corrupt":\(note.isCorrupt),
          "has_legacy_content":\(hasLegacyContent)
        }
        """
        copyToPasteboard(report)
        environment.toastCenter.show(message: "Issue report copied.", style: .success)
    }

    private func copyToPasteboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #endif
    }
}

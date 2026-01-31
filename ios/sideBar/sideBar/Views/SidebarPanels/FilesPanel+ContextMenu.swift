import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension FilesPanelView {
    @ViewBuilder
    func fileContextMenuItems(for item: IngestionListItem) -> some View {
        Button {
            Task {
                await viewModel.togglePinned(fileId: item.file.id, pinned: !(item.file.pinned ?? false))
            }
        } label: {
            Label(filePinTitle(for: item), systemImage: filePinIconName(for: item))
        }
        Button {
            beginRename(for: item)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            Task {
                await selectFileForAction(item)
                copySelectedFileContent()
            }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button {
            Task {
                await selectFileForAction(item)
                self.appEnvironment.emitShortcutAction(.openInDefaultApp)
            }
        } label: {
            Label("Download", systemImage: "square.and.arrow.down")
        }
        Button(role: .destructive) {
            deleteTarget = item
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func filePinTitle(for item: IngestionListItem) -> String {
        (item.file.pinned ?? false) ? "Unpin" : "Pin"
    }

    private func filePinIconName(for item: IngestionListItem) -> String {
        (item.file.pinned ?? false) ? "pin.slash" : "pin"
    }

    @MainActor
    private func selectFileForAction(_ item: IngestionListItem) async {
        await viewModel.selectFile(fileId: item.file.id)
    }

    private func beginRename(for item: IngestionListItem) {
        renameTarget = item
        renameValue = stripFileExtension(item.file.filenameOriginal)
        isRenameSheetPresented = true
    }

    func clearRenameTarget() {
        renameTarget = nil
        renameValue = ""
    }

    @MainActor
    func commitRename(to newName: String) async {
        guard let item = renameTarget else { return }
        let updatedName = applyFileExtension(originalName: item.file.filenameOriginal, newName: newName)
        let success = await viewModel.renameFile(fileId: item.file.id, filename: updatedName)
        if !success {
            self.appEnvironment.toastCenter.show(message: "Failed to rename file")
        }
        isRenameSheetPresented = false
        clearRenameTarget()
    }

    private func applyFileExtension(originalName: String, newName: String) -> String {
        guard let extensionRange = originalName.range(of: "\\.[^./]+$", options: .regularExpression) else {
            return newName
        }
        let fileExtension = originalName[extensionRange]
        let normalized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix(fileExtension) {
            return normalized
        }
        return normalized + fileExtension
    }

    private func copySelectedFileContent() {
        guard let text = viewModel.viewerState?.text, !text.isEmpty else {
            self.appEnvironment.toastCenter.show(message: "Copy unavailable for this file")
            return
        }
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
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
}

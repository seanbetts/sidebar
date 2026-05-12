import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension FilesPanelView {
    @ViewBuilder
    func fileContextMenuItems(for item: IngestionListItem) -> some View {
        sidebarMenuItemsView(fileContextMenuItemsList(for: item))
    }

    func fileContextMenuItemsList(for item: IngestionListItem) -> [SidebarMenuItem] {
        var items: [SidebarMenuItem] = [
            .pin(isPinned: item.file.pinned ?? false) {
                Haptics.selection()
                Task {
                    await viewModel.togglePinned(fileId: item.file.id, pinned: !(item.file.pinned ?? false))
                }
            },
            .rename {
                beginRename(for: item)
            },
            .download {
                Task {
                    await selectFileForAction(item)
                    self.appEnvironment.emitShortcutAction(.openInDefaultApp)
                }
            },
            .shareFile {
                Task { await shareFile(item) }
            },
            .delete {
                deleteTarget = item
                isDeleteAlertPresented = true
            }
        ]
        if viewModel.canCopyText(for: item) {
            items.insert(
                .copyText {
                    Task { await copyTextContent(for: item) }
                },
                at: 2
            )
        }
        return items
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

    @MainActor
    private func copyTextContent(for item: IngestionListItem) async {
        guard let text = await viewModel.loadCopyTextContent(fileId: item.file.id) else {
            self.appEnvironment.toastCenter.show(message: "Text unavailable for this file")
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
        self.appEnvironment.toastCenter.show(message: "Text copied", style: .success)
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

    @MainActor
    private func shareFile(_ item: IngestionListItem) async {
        do {
            let payload = try await viewModel.loadFileTransferPayload(fileId: item.file.id)
            let url = try FileShareAction.makeTemporaryShareURL(
                data: payload.data,
                filename: payload.filename,
                temporaryStore: viewModel.temporaryStore
            )
            SystemSharePresenter.share(url: url)
        } catch {
            self.appEnvironment.toastCenter.show(message: "Failed to share file")
        }
    }
}

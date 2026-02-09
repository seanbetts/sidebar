import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(iOS)
struct NoteActionsMenuButton: UIViewRepresentable {
    let title: String
    let pinTitle: String
    let pinIcon: String
    let archiveTitle: String
    let archiveIcon: String
    let isEnabled: Bool
    let onPin: () -> Void
    let onRename: () -> Void
    let onMove: () -> Void
    let onCopy: () -> Void
    let onDownload: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        button.configuration = config
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = title
        button.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.menu = makeMenu()
    }

    private func makeMenu() -> UIMenu {
        let pinAction = UIAction(title: pinTitle, image: UIImage(systemName: pinIcon)) { _ in
            onPin()
        }
        let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
            onRename()
        }
        let moveAction = UIAction(title: "Move", image: UIImage(systemName: "arrow.forward.folder")) { _ in
            onMove()
        }
        let copyAction = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
            onCopy()
        }
        let downloadAction = UIAction(title: "Download", image: UIImage(systemName: "square.and.arrow.down")) { _ in
            onDownload()
        }
        let archiveAction = UIAction(title: archiveTitle, image: UIImage(systemName: archiveIcon)) { _ in
            onArchive()
        }
        let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            onDelete()
        }
        return UIMenu(children: [
            pinAction,
            renameAction,
            moveAction,
            copyAction,
            downloadAction,
            archiveAction,
            deleteAction
        ])
    }
}
#endif

extension NotesDetailView {
    #if os(iOS)
    var noteToolbarMenu: some View {
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Note options",
            items: [
                SidebarMenuItem(title: pinActionTitle, systemImage: pinIconName, role: nil) {
                    guard let noteId = viewModel.activeNote?.path else { return }
                    Task {
                        await viewModel.setPinned(id: noteId, pinned: !isPinned)
                    }
                },
                SidebarMenuItem(title: "Rename", systemImage: "pencil", role: nil) {
                    renameValue = displayTitle
                    isRenameDialogPresented = true
                },
                SidebarMenuItem(title: "Move", systemImage: "arrow.forward.folder", role: nil) {
                    moveSelection = currentFolderPath
                    isMoveSheetPresented = true
                },
                SidebarMenuItem(title: "Copy", systemImage: "doc.on.doc", role: nil) {
                    copyMarkdown()
                },
                SidebarMenuItem(title: "Download", systemImage: "square.and.arrow.down", role: nil) {
                    exportMarkdown()
                },
                SidebarMenuItem(title: archiveMenuTitle, systemImage: archiveIconName, role: nil) {
                    archiveActiveNote()
                },
                SidebarMenuItem(title: "Delete", systemImage: "trash", role: .destructive) {
                    isDeleteAlertPresented = true
                }
            ],
            isCompact: isCompact
        )
        .disabled(viewModel.activeNote == nil)
    }
    #endif

    @ViewBuilder
    var noteActionsMenu: some View {
        #if os(macOS)
        Menu {
            noteActionsMenuItems
        } label: {
            HeaderActionIcon(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Note options")
        .disabled(viewModel.activeNote == nil)
        #else
        if isCompact {
            HeaderActionMenuButton(
                systemImage: "ellipsis",
                accessibilityLabel: "Note options",
                items: [
                    SidebarMenuItem(title: pinActionTitle, systemImage: pinIconName, role: nil) {
                        guard let noteId = viewModel.activeNote?.path else { return }
                        Task {
                            await viewModel.setPinned(id: noteId, pinned: !isPinned)
                        }
                    },
                    SidebarMenuItem(title: "Rename", systemImage: "pencil", role: nil) {
                        renameValue = displayTitle
                        isRenameDialogPresented = true
                    },
                    SidebarMenuItem(title: "Move", systemImage: "arrow.forward.folder", role: nil) {
                        moveSelection = currentFolderPath
                        isMoveSheetPresented = true
                    },
                    SidebarMenuItem(title: "Copy", systemImage: "doc.on.doc", role: nil) {
                        copyMarkdown()
                    },
                    SidebarMenuItem(title: "Download", systemImage: "square.and.arrow.down", role: nil) {
                        exportMarkdown()
                    },
                    SidebarMenuItem(title: archiveMenuTitle, systemImage: archiveIconName, role: nil) {
                        archiveActiveNote()
                    },
                    SidebarMenuItem(title: "Delete", systemImage: "trash", role: .destructive) {
                        isDeleteAlertPresented = true
                    }
                ],
                isCompact: isCompact
            )
            .disabled(viewModel.activeNote == nil)
        } else {
            NoteActionsMenuButton(
                title: "Note options",
                pinTitle: pinActionTitle,
                pinIcon: pinIconName,
                archiveTitle: archiveMenuTitle,
                archiveIcon: archiveIconName,
                isEnabled: viewModel.activeNote != nil,
                onPin: {
                    guard let noteId = viewModel.activeNote?.path else { return }
                    Task {
                        await viewModel.setPinned(id: noteId, pinned: !isPinned)
                    }
                },
                onRename: {
                    renameValue = displayTitle
                    isRenameDialogPresented = true
                },
                onMove: {
                    moveSelection = currentFolderPath
                    isMoveSheetPresented = true
                },
                onCopy: {
                    copyMarkdown()
                },
                onDownload: {
                    exportMarkdown()
                },
                onArchive: {
                    archiveActiveNote()
                },
                onDelete: {
                    isDeleteAlertPresented = true
                }
            )
            .frame(width: 28, height: 28)
            .fixedSize()
        }
        #endif
    }

    @ViewBuilder
    var noteActionsMenuItems: some View {
        Button {
            guard let noteId = viewModel.activeNote?.path else { return }
            Task {
                await viewModel.setPinned(id: noteId, pinned: !isPinned)
            }
        } label: {
            Label(pinActionTitle, systemImage: pinIconName)
        }
        Button {
            renameValue = displayTitle
            isRenameDialogPresented = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            moveSelection = currentFolderPath
            isMoveSheetPresented = true
        } label: {
            Label("Move", systemImage: "arrow.forward.folder")
        }
        Button {
            copyMarkdown()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button {
            exportMarkdown()
        } label: {
            Label("Download", systemImage: "square.and.arrow.down")
        }
        Button {
            archiveActiveNote()
        } label: {
            Label(archiveMenuTitle, systemImage: archiveIconName)
        }
        Button(role: .destructive) {
            isDeleteAlertPresented = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    var closeButton: some View {
        HeaderActionButton(
            systemName: "xmark",
            accessibilityLabel: "Close note",
            action: {
                requestCloseNote()
            },
            isDisabled: viewModel.activeNote == nil
        )
    }
}

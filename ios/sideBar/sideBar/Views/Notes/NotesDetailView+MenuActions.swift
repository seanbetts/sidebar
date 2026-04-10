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
    let onMove: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void
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
        let moveAction = UIAction(title: "Move", image: UIImage(systemName: "arrow.forward.folder")) { _ in
            onMove()
        }
        let copyAction = UIAction(title: "Copy Text", image: UIImage(systemName: "doc.on.doc")) { _ in
            onCopy()
        }
        let shareAction = UIAction(title: "Share Text", image: UIImage(systemName: "square.and.arrow.up.on.square")) { _ in
            onShare()
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
            moveAction,
            copyAction,
            shareAction,
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
            items: noteSidebarMenuItems,
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
                items: noteSidebarMenuItems,
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
                    togglePinnedForActiveNote()
                },
                onMove: {
                    moveSelection = currentFolderPath
                    isMoveSheetPresented = true
                },
                onCopy: {
                    copyNoteText()
                },
                onShare: {
                    shareNoteText()
                },
                onDownload: {
                    exportNoteText()
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

    private var noteSidebarMenuItems: [SidebarMenuItem] {
        [
            .pin(isPinned: isPinned) {
                togglePinnedForActiveNote()
            },
            .move {
                moveSelection = currentFolderPath
                isMoveSheetPresented = true
            },
            .copyText {
                copyNoteText()
            },
            .shareText {
                shareNoteText()
            },
            .download {
                exportNoteText()
            },
            .archive(isArchived: isArchived) {
                archiveActiveNote()
            },
            .delete {
                isDeleteAlertPresented = true
            }
        ]
    }

    @ViewBuilder
    var noteActionsMenuItems: some View {
        Button {
            togglePinnedForActiveNote()
        } label: {
            Label(pinActionTitle, systemImage: pinIconName)
        }
        Button {
            moveSelection = currentFolderPath
            isMoveSheetPresented = true
        } label: {
            Label("Move", systemImage: "arrow.forward.folder")
        }
        Button {
            copyNoteText()
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }
        Button {
            shareNoteText()
        } label: {
            Label("Share Text", systemImage: "square.and.arrow.up.on.square")
        }
        Button {
            exportNoteText()
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

    @ViewBuilder
    var closeButton: some View {
        HeaderActionButton(
            systemName: "xmark",
            accessibilityLabel: "Close note",
            action: {
                requestCloseNote()
            },
            isDisabled: viewModel.activeNote == nil
        )
        .keyboardShortcut(.escape, modifiers: [])
    }
}

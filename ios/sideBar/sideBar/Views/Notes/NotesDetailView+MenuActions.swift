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
        let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
            onRename()
        }
        let moveAction = UIAction(title: "Move", image: UIImage(systemName: "arrow.forward.folder")) { _ in
            onMove()
        }
        let copyAction = UIAction(title: "Copy Markdown", image: UIImage(systemName: "doc.on.doc")) { _ in
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
            renameAction,
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
                onShare: {
                    shareMarkdown()
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

    private var noteSidebarMenuItems: [SidebarMenuItem] {
        [
            .pin(isPinned: isPinned) {
                guard let noteId = viewModel.activeNote?.path else { return }
                Task {
                    await viewModel.setPinned(id: noteId, pinned: !isPinned)
                }
            },
            .rename {
                renameValue = displayTitle
                isRenameDialogPresented = true
            },
            .move {
                moveSelection = currentFolderPath
                isMoveSheetPresented = true
            },
            .copyMarkdown {
                copyMarkdown()
            },
            .shareText {
                shareMarkdown()
            },
            .download {
                exportMarkdown()
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
            Label("Copy Markdown", systemImage: "doc.on.doc")
        }
        Button {
            shareMarkdown()
        } label: {
            Label("Share Text", systemImage: "square.and.arrow.up.on.square")
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

    @ViewBuilder
    var closeButton: some View {
        if editorViewModel.isReadOnly {
            HeaderActionButton(
                systemName: "xmark",
                accessibilityLabel: "Close note",
                action: {
                    requestCloseNote()
                },
                isDisabled: viewModel.activeNote == nil
            )
            .keyboardShortcut(.escape, modifiers: [])
        } else {
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
}

struct NoteContentQuickActionsPill: View {
    let isPinned: Bool
    let isArchived: Bool
    let onPinToggle: () -> Void
    let onArchiveToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            iconButton(
                systemName: isPinned ? "pin.slash" : "pin",
                accessibilityLabel: isPinned ? "Unpin note" : "Pin note",
                role: nil,
                action: onPinToggle
            )
            divider
            iconButton(
                systemName: isArchived ? "archivebox.fill" : "archivebox",
                accessibilityLabel: isArchived ? "Unarchive note" : "Archive note",
                role: nil,
                action: onArchiveToggle
            )
            divider
            iconButton(
                systemName: "trash",
                accessibilityLabel: "Delete note",
                role: .destructive,
                action: onDelete
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .appShadow(
            color: Color.black.opacity(0.12),
            radius: DesignTokens.Spacing.sm,
            y: DesignTokens.Spacing.xs
        )
    }

    @ViewBuilder
    private func iconButton(
        systemName: String,
        accessibilityLabel: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(DesignTokens.Typography.labelMd)
                .frame(width: 22, height: 22)
                .foregroundStyle(
                    role == .destructive ? DesignTokens.Colors.error : DesignTokens.Colors.textPrimary
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.border)
            .frame(width: 1, height: 14)
    }
}

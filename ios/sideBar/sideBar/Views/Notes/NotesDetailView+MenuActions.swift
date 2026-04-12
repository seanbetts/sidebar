import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension NotesDetailView {
    #if os(iOS)
    var noteToolbarMenu: some View {
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Note options",
            items: noteSidebarMenuItems,
            isCompact: isCompact,
            chromeStyle: .plain
        )
        .systemShareAnchor(id: SystemShareAnchorID.notesToolbarActionsMenu)
        .disabled(viewModel.activeNote == nil)
    }
    #endif

    @ViewBuilder
    var noteActionsMenu: some View {
        #if os(macOS)
        HeaderActionMenuControl(
            systemName: "ellipsis",
            accessibilityLabel: "Note options",
            chromeStyle: Self.actionControlChromeStyle
        ) {
            noteActionsMenuItems
        }
        .systemShareAnchor(id: SystemShareAnchorID.notesHeaderActionsMenu)
        .disabled(viewModel.activeNote == nil)
        #else
        if isCompact {
            HeaderActionMenuButton(
                systemImage: "ellipsis",
                accessibilityLabel: "Note options",
                items: noteSidebarMenuItems,
                isCompact: isCompact,
                chromeStyle: Self.actionControlChromeStyle
            )
            .systemShareAnchor(id: SystemShareAnchorID.notesHeaderActionsMenu)
            .disabled(viewModel.activeNote == nil)
        } else {
            HeaderActionMenuButton(
                systemImage: "ellipsis",
                accessibilityLabel: "Note options",
                items: noteSidebarMenuItems,
                isCompact: isCompact,
                chromeStyle: Self.actionControlChromeStyle
            )
            .systemShareAnchor(id: SystemShareAnchorID.notesHeaderActionsMenu)
            .disabled(viewModel.activeNote == nil)
        }
        #endif
    }

    private var noteSidebarMenuItems: [SidebarMenuItem] {
        [
            .pin(isPinned: isPinned) {
                togglePinnedForActiveNote()
            },
            .rename {
                beginRenameForActiveNote()
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
            beginRenameForActiveNote()
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
            isDisabled: viewModel.activeNote == nil,
            chromeStyle: Self.actionControlChromeStyle
        )
        .keyboardShortcut(.escape, modifiers: [])
    }

    func beginRenameForActiveNote() {
        renameValue = displayTitle
        isRenameAlertPresented = true
    }
}

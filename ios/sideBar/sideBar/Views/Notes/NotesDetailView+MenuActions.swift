import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension NotesDetailView {
    #if os(iOS)
    var noteToolbarMenu: some View {
        HeaderActionMenuButton(
            icon: AppIcon.Action.more,
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
            icon: AppIcon.Action.more,
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
                icon: AppIcon.Action.more,
                accessibilityLabel: "Note options",
                items: noteSidebarMenuItems,
                isCompact: isCompact,
                chromeStyle: Self.actionControlChromeStyle
            )
            .systemShareAnchor(id: SystemShareAnchorID.notesHeaderActionsMenu)
            .disabled(viewModel.activeNote == nil)
        } else {
            HeaderActionMenuButton(
                icon: AppIcon.Action.more,
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
        sidebarMenuItemsView(noteSidebarMenuItems)
    }

    @ViewBuilder
    var closeButton: some View {
        HeaderActionButton(
            icon: AppIcon.Action.close,
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

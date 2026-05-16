import Foundation
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

public struct NotesPanel: View {
    @EnvironmentObject var environment: AppEnvironment
    @StateObject private var pinnedReorderState = NotesPanelPinnedReorderState()

    public init() {
    }

    public var body: some View {
        NotesPanelView(
            viewModel: environment.notesRuntime.viewModel,
            pinnedReorderState: pinnedReorderState
        )
    }
}

struct NotesPanelView: View {
    static let actionControlChromeStyle: HeaderActionControlChromeStyle = .glass

    @ObservedObject var viewModel: NotesViewModel
    @EnvironmentObject var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) var colorScheme
    @State var pinnedReorderNetworkAvailabilityOverride: Bool?
    @State var pinnedReorderAutoExitDelayOverride: TimeInterval?
    let pinnedReorderState: NotesPanelPinnedReorderState
    @State var isArchiveExpanded = false
    @State var expandedFolderIDs: Set<String> = []
    @State var isNewFolderPresented = false
    @State var newFolderName: String = ""
    @State var newFolderParent: String = ""
    @State var isCreatingNote = false
    @State var isCreatingFolder = false
    @State var renameTarget: FileNodeItem?
    @State var renameValue: String = ""
    @State var deleteTarget: FileNodeItem?
    @State var moveTargetId: String?
    @State var moveSelection: String = ""
    @State var isMoveSheetPresented = false
    @State var exportDocument: PlainTextFileDocument?
    @State var isExporting = false
    @State var exportFilename: String = "note"
    @FocusState var isSearchFocused: Bool

    @MainActor
    init(
        viewModel: NotesViewModel,
        pinnedReorderState: NotesPanelPinnedReorderState? = nil,
        pinnedReorderNetworkAvailability: Bool? = nil,
        pinnedReorderAutoExitDelay: TimeInterval? = nil
    ) {
        self.viewModel = viewModel
        self.pinnedReorderState = pinnedReorderState ?? NotesPanelPinnedReorderState()
        _pinnedReorderNetworkAvailabilityOverride = State(
            initialValue: pinnedReorderNetworkAvailability
        )
        _pinnedReorderAutoExitDelayOverride = State(
            initialValue: pinnedReorderAutoExitDelay
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            notesPanelContent
        }
        .sidebarPanelScaffoldBackground()
        .frame(maxHeight: .infinity)
        .onAppear {
            synchronizeExpandedFolderState()
            consumePendingNewNoteDeepLinkIfNeeded()
        }
        .onChange(of: environment.pendingSidebarDeepLink) { _, _ in
            consumePendingNewNoteDeepLinkIfNeeded()
        }
        .onChange(of: viewModel.searchQuery) { _, newValue in
            viewModel.updateSearch(query: newValue)
        }
        .onChange(of: isArchiveExpanded) { _, expanded in
            if expanded {
                Task { await viewModel.loadArchivedTree() }
            }
        }
        .onChange(of: folderExpansionSeed) { _, _ in
            synchronizeExpandedFolderState()
        }
        .sheet(isPresented: $isNewFolderPresented) {
            NewFolderSheet(
                name: $newFolderName,
                selectedFolder: $newFolderParent,
                options: folderOptions,
                isSaving: isCreatingFolder,
                onCreate: createFolder
            )
            .phoneSheetGrabBarVisible()
        }
        .sheet(isPresented: $isMoveSheetPresented) {
            NoteFolderPickerSheet(
                title: "Move Note",
                selection: $moveSelection,
                options: moveFolderOptions,
                onConfirm: { selection in
                    guard let targetId = moveTargetId else { return }
                    Task {
                        await viewModel.moveNote(id: targetId, folder: selection)
                    }
                }
            )
            .phoneSheetGrabBarVisible()
        }
        .alert(renameDialogTitle, isPresented: isRenameDialogPresented) {
            TextField(renameDialogPlaceholder, text: $renameValue)
                .submitLabel(.done)
                .onSubmit {
                    commitRename()
                }
            Button("Rename") {
                commitRename()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
                renameValue = ""
            }
        }
        .deleteConfirmationAlert(
            title: deleteDialogTitle,
            isPresented: isDeleteDialogPresented,
            message: deleteDialogMessage,
            confirmAsDefaultAction: true,
            onConfirm: {
                let target = deleteTarget
                deleteTarget = nil
                Task {
                    if let target {
                        if target.isFile {
                            if viewModel.selectedNoteId == target.id {
                                await deleteNoteAfterDismissal(id: target.id)
                            } else {
                                await viewModel.deleteNote(id: target.id)
                            }
                        } else {
                            await viewModel.deleteFolder(path: target.id)
                        }
                    }
                }
            },
            onCancel: {
                deleteTarget = nil
            }
        )
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event, event.section == .notes else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .newItem:
                createBlankNote()
            case .createFolder:
                newFolderName = ""
                newFolderParent = ""
                isNewFolderPresented = true
            case .navigateList(let direction):
                navigateNotesList(direction: direction)
            default:
                break
            }
        }
    }

    func prepareForDestructiveAction() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    func deleteNoteAfterDismissal(id: String) async {
        prepareForDestructiveAction()
        await waitForKeyboardDismissal()
        await viewModel.deleteNote(id: id)
    }

    @MainActor
    func waitForKeyboardDismissal(timeout: UInt64 = 500_000_000) async {
        #if os(iOS)
        let notifications = NotificationCenter.default.notifications(named: UIResponder.keyboardDidHideNotification)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in notifications {
                    break
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeout)
            }
            await group.next()
            group.cancelAll()
        }
        #endif
    }

    private func consumePendingNewNoteDeepLinkIfNeeded() {
        guard environment.consumePendingSidebarDeepLink(host: "notes", path: "/new") != nil else { return }
        createBlankNoteFromDeepLink()
    }

}

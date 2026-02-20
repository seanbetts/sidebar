import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct NotesDetailView: View {
    @ObservedObject var viewModel: NotesViewModel
    @ObservedObject var editorViewModel: NotesEditorViewModel
    private let contentMaxWidth: CGFloat = SideBarMarkdownLayout.maxContentWidth
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var isRenameDialogPresented: Bool
    @Binding var renameValue: String
    @Binding var isMoveSheetPresented: Bool
    @Binding var moveSelection: String
    @Binding var isDeleteAlertPresented: Bool
    @Binding var isCloseConfirmPresented: Bool
    @Binding var isExporting: Bool
    @Binding var exportDocument: MarkdownFileDocument?
    @Binding var exportFilename: String
    @State private var quickActionsNoteId: String?
    @State private var showSavedIndicator = false
    @State private var lastSavedTimestamp: TimeInterval = 0
    @State private var savedIndicatorTask: Task<Void, Never>?
    @Environment(\.workspaceColumn) private var workspaceColumn
    @AppStorage(AppStorageKeys.workspaceExpanded) private var isWorkspaceExpanded: Bool = false
    #if os(iOS)
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) private var isWorkspaceExpandedByRotation: Bool = false
    #endif
    @AppStorage(AppStorageKeys.useNativeMarkdownEditor) private var useNativeMarkdownEditor = true
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if !isCompact {
                header
                Divider()
            }
            contentWithToolbar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: editorViewModel.lastSavedAt) { _, newValue in
            handleSavedIndicatorChange(newValue)
        }
        .onChange(of: editorViewModel.isDirty) { _, isDirty in
            if isDirty {
                hideSavedIndicator()
            }
        }
        .onChange(of: editorViewModel.isSaving) { _, isSaving in
            if isSaving {
                hideSavedIndicator()
            }
        }
        .onChange(of: editorViewModel.currentNoteId) { _, _ in
            resetSavedIndicator()
        }
        .onDisappear {
            savedIndicatorTask?.cancel()
        }
        .sheet(item: conflictBinding) { conflict in
            ConflictResolutionSheet(conflict: conflict) { choice in
                Task {
                    await handleConflictChoice(choice)
                }
            }
            .interactiveDismissDisabled(true)
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event, event.section == .notes else { return }
            switch event.action {
            case .closeItem:
                requestCloseNote()
            case .renameItem:
                guard viewModel.activeNote != nil else { return }
                renameValue = displayTitle
                isRenameDialogPresented = true
            case .deleteItem:
                guard viewModel.activeNote != nil else { return }
                isDeleteAlertPresented = true
            case .archiveItem:
                archiveActiveNote()
            default:
                break
            }
        }
        .onChange(of: viewModel.activeNote?.id) { _, newValue in
            guard quickActionsNoteId != newValue else { return }
            hideQuickActionsPill()
        }
        #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let activeNote = viewModel.activeNote, quickActionsNoteId == activeNote.id {
                NoteContentQuickActionsPill(
                    isPinned: isPinned,
                    isArchived: isArchived,
                    onPinToggle: {
                        togglePinnedForActiveNote()
                    },
                    onArchiveToggle: {
                        hideQuickActionsPill()
                        archiveActiveNote()
                    },
                    onDelete: {
                        hideQuickActionsPill()
                        isDeleteAlertPresented = true
                    }
                )
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            .easeInOut(duration: DesignTokens.Animation.standard),
            value: quickActionsNoteId
        )
        .toolbar {
            if isCompact, viewModel.activeNote != nil, isPhone {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    noteToolbarMenu
                }
            }
        }
        #endif
    }
}

extension NotesDetailView {
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            ContentHeaderRow(
                iconName: "text.document",
                title: displayTitle,
                subtitle: createdDateSubtitle,
                titleFont: .subheadline.weight(.semibold),
                titleSubtitleAxis: .vertical
            , trailing: {
                if viewModel.activeNote != nil {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        if let status = noteStatus {
                            noteStatusText(status)
                        }
                        HeaderActionRow {
                            #if os(iOS)
                            if shouldShowExpandButton {
                                expandButton
                            }
                            #endif
                            noteActionsMenu
                            closeButton
                        }
                    }
                }
            })
            .padding(DesignTokens.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    private var createdDateSubtitle: String? {
        guard let created = viewModel.activeNote?.created else {
            return nil
        }
        let date = Date(timeIntervalSince1970: created)
        return Self.createdDateFormatter.string(from: date)
    }

    private static let createdDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    @ViewBuilder
    private var content: some View {
        if let activeNote = viewModel.activeNote {
            if #available(iOS 26.0, macOS 26.0, *), useNativeMarkdownEditor {
                NativeMarkdownEditorContainer(
                    editorViewModel: editorViewModel,
                    maxContentWidth: contentMaxWidth
                )
                #if os(iOS)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        toggleQuickActionsPill(for: activeNote.id)
                    }
                )
                #endif
            } else {
                SideBarMarkdownContainer(text: editorViewModel.content)
                    .onAppear {
                        editorViewModel.setReadOnly(true)
                    }
                    #if os(iOS)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            toggleQuickActionsPill(for: activeNote.id)
                        }
                    )
                    #endif
            }
        } else if viewModel.selectedNoteId != nil {
            if let error = viewModel.errorMessage {
                PlaceholderView(
                    title: "Unable to load note",
                    subtitle: environment.isOffline ? "This note isn't available offline yet." : error,
                    actionTitle: "Retry"
                ) {
                    guard let selectedId = viewModel.selectedNoteId else { return }
                    Task { await viewModel.loadNote(id: selectedId) }
                }
            } else if !environment.isNetworkAvailable {
                PlaceholderView(
                    title: "Unable to load note",
                    subtitle: "This note isn't available offline yet.",
                    actionTitle: "Retry"
                ) {
                    guard let selectedId = viewModel.selectedNoteId else { return }
                    Task { await viewModel.loadNote(id: selectedId) }
                }
            } else {
                LoadingView(message: "Loading note…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            #if os(macOS)
            if viewModel.tree == nil {
                LoadingView(message: "Loading notes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WelcomeEmptyView()
            }
            #else
            if viewModel.tree == nil {
                LoadingView(message: "Loading notes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PlaceholderView(
                    title: "Select a note",
                    subtitle: "Choose a note from the sidebar to start reading.",
                    iconName: "text.document"
                )
            }
            #endif
        }
    }

    private var contentWithToolbar: some View {
        VStack(spacing: 0) {
            if isCompact, viewModel.activeNote != nil, let status = noteStatus {
                HStack {
                    Spacer()
                    noteStatusText(status)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                Divider()
            }
            content
        }
    }

    private struct NoteStatus: Equatable {
        let text: String
        let color: Color
    }

    private var noteStatus: NoteStatus? {
        if editorViewModel.isSaving {
            return NoteStatus(text: "Saving...", color: DesignTokens.Colors.textSecondary)
        }
        if editorViewModel.isQueuedForSync {
            let label = environment.isNetworkAvailable ? "Queued to sync" : "Saved offline"
            return NoteStatus(text: label, color: DesignTokens.Colors.textSecondary)
        }
        if let error = editorViewModel.saveErrorMessage, !error.isEmpty {
            return NoteStatus(text: error, color: DesignTokens.Colors.error)
        }
        if editorViewModel.isDirty {
            return NoteStatus(text: "Unsaved changes", color: DesignTokens.Colors.textSecondary)
        }
        if let label = lastSavedLabel {
            return NoteStatus(text: "Saved \(label)", color: DesignTokens.Colors.textSecondary)
        }
        return nil
    }

    private var lastSavedLabel: String? {
        guard showSavedIndicator, let lastSaved = editorViewModel.lastSavedAt else { return nil }
        return formatLastSaved(lastSaved)
    }

    private func noteStatusText(_ status: NoteStatus) -> some View {
        Text(status.text)
            .font(.caption)
            .foregroundStyle(status.color)
            .lineLimit(1)
    }

    private func formatLastSaved(_ date: Date) -> String {
        let now = Date()
        let diffSeconds = Int(now.timeIntervalSince(date))
        if diffSeconds < 60 {
            return "just now"
        }
        if diffSeconds < 3600 {
            return "\(diffSeconds / 60)m ago"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func handleSavedIndicatorChange(_ date: Date?) {
        guard let date else { return }
        let timestamp = date.timeIntervalSince1970
        guard timestamp != lastSavedTimestamp else { return }
        lastSavedTimestamp = timestamp
        guard !editorViewModel.isDirty, !editorViewModel.isSaving else { return }
        showSavedIndicator = true
        savedIndicatorTask?.cancel()
        savedIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            showSavedIndicator = false
        }
    }

    private func hideSavedIndicator() {
        showSavedIndicator = false
        savedIndicatorTask?.cancel()
        savedIndicatorTask = nil
    }

    private func resetSavedIndicator() {
        hideSavedIndicator()
        lastSavedTimestamp = 0
    }

    private func toggleQuickActionsPill(for noteId: String) {
        withAnimation {
            quickActionsNoteId = quickActionsNoteId == noteId ? nil : noteId
        }
    }

    private func hideQuickActionsPill() {
        withAnimation {
            quickActionsNoteId = nil
        }
    }

    private func togglePinnedForActiveNote() {
        guard let noteId = viewModel.activeNote?.path else { return }
        Task {
            await viewModel.setPinned(id: noteId, pinned: !isPinned)
        }
    }

    private var conflictBinding: Binding<NoteSyncConflict?> {
        Binding(
            get: { editorViewModel.conflict },
            set: { _ in }
        )
    }

    private func handleConflictChoice(_ choice: NoteConflictChoice) async {
        switch choice {
        case .keepLocal:
            await editorViewModel.resolveConflictKeepLocal()
        case .keepServer:
            await editorViewModel.resolveConflictKeepServer()
        case .keepBoth:
            await editorViewModel.resolveConflictKeepBoth()
        }
    }

    var displayTitle: String {
        guard let name = viewModel.activeNote?.name else {
            return "Notes"
        }
        if name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    #if os(iOS)
    var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var shouldShowExpandButton: Bool {
        guard workspaceColumn == .primary else { return false }
        #if os(iOS)
        return !isPhone
        #else
        return true
        #endif
    }

    private var expandButton: some View {
        Button(action: expandNoteView) {
            Image(systemName: expandButtonIconName)
                .font(DesignTokens.Typography.labelMd)
                .frame(width: 28, height: 20)
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expandButtonLabel)
        .disabled(viewModel.activeNote == nil)
    }

    private var expandButtonIconName: String {
        isWorkspaceExpanded ? "arrow.up.right.and.arrow.down.left" : "arrow.down.left.and.arrow.up.right"
    }

    private var expandButtonLabel: String {
        isWorkspaceExpanded ? "Exit expanded mode" : "Expand note"
    }

    private func expandNoteView() {
        #if os(iOS)
        if !isPhone {
            isWorkspaceExpandedByRotation = false
        }
        #endif
        isWorkspaceExpanded.toggle()
    }
    #endif
}

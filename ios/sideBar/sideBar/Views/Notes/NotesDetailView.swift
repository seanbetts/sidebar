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
    let contentMaxWidth: CGFloat = NoteTextLayout.maxContentWidth
    @EnvironmentObject var environment: AppEnvironment
    @Binding var isMoveSheetPresented: Bool
    @Binding var moveSelection: String
    @Binding var isDeleteAlertPresented: Bool
    @Binding var isExporting: Bool
    @Binding var exportDocument: PlainTextFileDocument?
    @Binding var exportFilename: String
    #if os(iOS)
    var formattingBarPresentationOverride: NoteFormattingBarPresentation?
    #endif
    @State private var showSavedIndicator = false
    @State private var lastSavedTimestamp: TimeInterval = 0
    @State private var savedIndicatorTask: Task<Void, Never>?
    @State var isHoldingEditorSurfaceDuringReadExit = false
    @State var pendingReadExitHoldTargetOffset: CGPoint?
    #if os(iOS)
    @State private var activeFormattingBarPresentation: NoteFormattingBarPresentation?
    #endif
    @Environment(\.workspaceColumn) private var workspaceColumn
    @AppStorage(AppStorageKeys.workspaceExpanded) var isWorkspaceExpanded: Bool = false
    #if os(iOS)
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) var isWorkspaceExpandedByRotation: Bool = false
    #endif
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    #if os(iOS)
    init(
        viewModel: NotesViewModel,
        editorViewModel: NotesEditorViewModel,
        isMoveSheetPresented: Binding<Bool>,
        moveSelection: Binding<String>,
        isDeleteAlertPresented: Binding<Bool>,
        isExporting: Binding<Bool>,
        exportDocument: Binding<PlainTextFileDocument?>,
        exportFilename: Binding<String>,
        formattingBarPresentationOverride: NoteFormattingBarPresentation? = nil
    ) {
        self.viewModel = viewModel
        self.editorViewModel = editorViewModel
        self._isMoveSheetPresented = isMoveSheetPresented
        self._moveSelection = moveSelection
        self._isDeleteAlertPresented = isDeleteAlertPresented
        self._isExporting = isExporting
        self._exportDocument = exportDocument
        self._exportFilename = exportFilename
        self.formattingBarPresentationOverride = formattingBarPresentationOverride
    }
    #else
    init(
        viewModel: NotesViewModel,
        editorViewModel: NotesEditorViewModel,
        isMoveSheetPresented: Binding<Bool>,
        moveSelection: Binding<String>,
        isDeleteAlertPresented: Binding<Bool>,
        isExporting: Binding<Bool>,
        exportDocument: Binding<PlainTextFileDocument?>,
        exportFilename: Binding<String>
    ) {
        self.viewModel = viewModel
        self.editorViewModel = editorViewModel
        self._isMoveSheetPresented = isMoveSheetPresented
        self._moveSelection = moveSelection
        self._isDeleteAlertPresented = isDeleteAlertPresented
        self._isExporting = isExporting
        self._exportDocument = exportDocument
        self._exportFilename = exportFilename
    }
    #endif
    var body: some View {
        VStack(spacing: 0) {
            if !isCompact, !isShowingWelcomeHome {
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
            #if os(iOS)
            activeFormattingBarPresentation = nil
            isHoldingEditorSurfaceDuringReadExit = false
            pendingReadExitHoldTargetOffset = nil
            #endif
        }
        .onChange(of: editorViewModel.presentationMode) { _, newMode in
            #if os(iOS)
            if newMode != .edit {
                activeFormattingBarPresentation = nil
            }
            if newMode == .read {
                pendingReadExitHoldTargetOffset = editorViewModel.pendingReadSurfaceViewportOffset
                if pendingReadExitHoldTargetOffset != nil {
                    isHoldingEditorSurfaceDuringReadExit = true
                }
            } else {
                isHoldingEditorSurfaceDuringReadExit = false
                pendingReadExitHoldTargetOffset = nil
            }
            #endif
        }
        #if os(iOS)
        .onChange(of: editorViewModel.pendingReadSurfaceViewportOffset) { _, newOffset in
            if let newOffset {
                pendingReadExitHoldTargetOffset = newOffset
                if isHoldingEditorSurfaceDuringReadExit {
                    isHoldingEditorSurfaceDuringReadExit = true
                }
            }
        }
        #endif
        .onDisappear {
            savedIndicatorTask?.cancel()
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            handleShortcutActionEvent(event, workspacePane: workspaceColumn.workspacePane)
        }
        #if os(iOS)
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
                titleAccessory: noteStatusTitleAccessory,
                subtitle: createdDateSubtitle,
                titleStyle: .subheadline,
                titleWeight: .semibold,
                titleSubtitleAxis: .vertical
            , trailing: {
                if viewModel.activeNote != nil {
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
        if isCompactPhoneRoutePendingSelection {
            LoadingView(message: "Loading note…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.activeNote != nil {
            if isShowingUnsupportedContentPlaceholder {
                PlaceholderView(
                    title: unsupportedContentPlaceholderTitle,
                    subtitle: unsupportedContentPlaceholderMessage,
                    iconName: "exclamationmark.triangle"
                )
            } else {
                supportedNoteSurface
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
            if viewModel.tree == nil {
                LoadingView(message: "Loading notes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WelcomeEmptyView()
            }
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
            contentOverlayRegion
        }
    }

    @ViewBuilder
    private var contentOverlayRegion: some View {
        content
            .overlay(alignment: .topTrailing) {
                if isCustomFormattingBarVisible {
                    noteFormattingBar
                        .padding(.top, DesignTokens.Spacing.sm)
                        .padding(.trailing, DesignTokens.Spacing.md)
                }
            }
    }

    private struct NoteStatus: Equatable {
        let iconName: String
        let accessibilityLabel: String
        let helpText: String
        let color: Color
    }

    private var isCompactPhoneRoutePendingSelection: Bool {
        Self.isCompactPhoneRoutePendingSelection(
            isCompact: isCompact, routeNoteId: environment.notesPhoneDetailRouteId, selectedNoteId: viewModel.selectedNoteId
        )
    }

    static func isCompactPhoneRoutePendingSelection(
        isCompact: Bool,
        routeNoteId: String?,
        selectedNoteId: String?
    ) -> Bool {
        guard isCompact, let routeNoteId else { return false }
        return routeNoteId != selectedNoteId
    }

    private var noteStatus: NoteStatus? {
        if editorViewModel.isSaving {
            return NoteStatus(
                iconName: "arrow.triangle.2.circlepath",
                accessibilityLabel: "Saving",
                helpText: "Saving",
                color: .primary
            )
        }
        if editorViewModel.isQueuedForSync {
            let label = environment.isNetworkAvailable ? "Queued to sync" : "Saved offline"
            return NoteStatus(
                iconName: "icloud.and.arrow.up",
                accessibilityLabel: label,
                helpText: label,
                color: .primary
            )
        }
        if let error = editorViewModel.saveErrorMessage, !error.isEmpty {
            return NoteStatus(
                iconName: "exclamationmark.triangle.fill",
                accessibilityLabel: "Save error",
                helpText: error,
                color: DesignTokens.Colors.error
            )
        }
        if editorViewModel.isDirty {
            return NoteStatus(
                iconName: "pencil.circle.fill",
                accessibilityLabel: "Unsaved changes",
                helpText: "Unsaved changes",
                color: .primary
            )
        }
        if let label = lastSavedLabel {
            return NoteStatus(
                iconName: "checkmark.circle.fill",
                accessibilityLabel: "Saved \(label)",
                helpText: "Saved \(label)",
                color: .primary
            )
        }
        return nil
    }

    private var lastSavedLabel: String? {
        guard showSavedIndicator, let lastSaved = editorViewModel.lastSavedAt else { return nil }
        return formatLastSaved(lastSaved)
    }

    private func noteStatusText(_ status: NoteStatus) -> some View {
        Image(systemName: status.iconName)
            .appFont(.size16Semibold)
            .frame(width: 32, height: 22)
            .imageScale(.medium)
            .foregroundStyle(status.color)
            .accessibilityLabel(status.accessibilityLabel)
            .help(status.helpText)
    }

    private var noteStatusTitleAccessory: AnyView? {
        guard let status = noteStatus else { return nil }
        return AnyView(
            noteStatusText(status)
                .padding(.leading, 8)
        )
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

    var displayTitle: String { viewModel.activeNote?.name ?? "Notes" }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var isShowingWelcomeHome: Bool {
        viewModel.activeNote == nil
            && viewModel.selectedNoteId == nil
            && viewModel.tree != nil
    }

    var formattingBarPresentation: NoteFormattingBarPresentation {
        guard isShowingEditorSurface else { return .hidden }
        #if os(iOS)
        if let formattingBarPresentationOverride {
            return formattingBarPresentationOverride
        }
        return activeFormattingBarPresentation ?? defaultEditingFormattingBarPresentation
        #else
        return .floatingTopTrailing
        #endif
    }

    #if os(iOS)
    var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private var defaultEditingFormattingBarPresentation: NoteFormattingBarPresentation {
        .floatingTopTrailing
    }

    func handleFormattingBarPresentationChange(_ presentation: NoteFormattingBarPresentation) {
        activeFormattingBarPresentation = presentation
    }

    private var shouldShowExpandButton: Bool {
        WorkspaceBehaviorPolicy.shouldShowExpandButton(
            workspaceColumn: workspaceColumn,
            isPhoneIdiom: {
                #if os(iOS)
                isPhone
                #else
                false
                #endif
            }()
        )
    }

    private var expandButton: some View {
        Button(action: expandNoteView) {
            Image(systemName: expandButtonIconName)
                .appFont(.labelMd)
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
    private var expandButtonLabel: String { isWorkspaceExpanded ? "Exit expanded mode" : "Expand note" }

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

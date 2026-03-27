import SwiftUI
#if os(iOS)
import Combine
import UIKit
#endif

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorContainer: View {
    enum EditorSurfaceKind: Equatable {
        case swiftUI
        case appKit
        case uiKit
    }

    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    let autofocusEnabled: Bool
    let onFormattingBarPresentationChange: ((NoteFormattingBarPresentation) -> Void)?
    let onInitialPresentationReady: (() -> Void)?
    let onEscape: ((NotesSemanticDocument) -> Void)?
    @EnvironmentObject var environment: AppEnvironment

    @StateObject private var nativeViewModel: NativeNoteEditorViewModel
    @State private var loadedNoteId: String?
    @State private var pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?
    @State private var pendingSelectionViewportAnchorY: CGFloat?
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue
    #if os(iOS)
    @State private var isSoftwareKeyboardVisible = false
    #endif

    init(
        editorViewModel: NotesEditorViewModel,
        maxContentWidth: CGFloat,
        autofocusEnabled: Bool = true,
        onFormattingBarPresentationChange: ((NoteFormattingBarPresentation) -> Void)? = nil,
        onInitialPresentationReady: (() -> Void)? = nil,
        onEscape: ((NotesSemanticDocument) -> Void)?
    ) {
        self.editorViewModel = editorViewModel
        self.maxContentWidth = maxContentWidth
        self.autofocusEnabled = autofocusEnabled
        self.onFormattingBarPresentationChange = onFormattingBarPresentationChange
        self.onInitialPresentationReady = onInitialPresentationReady
        self.onEscape = onEscape
        _nativeViewModel = StateObject(wrappedValue: editorViewModel.sharedNativeEditor())
    }

    var body: some View {
        editorSurface
        .onAppear {
            nativeViewModel.setBaseFontSize(editorBaseFontSize)
            editorViewModel.attachNativeEditor(nativeViewModel)
            loadIfNeeded()
            applyAutosaveDelay(isOffline: environment.isOffline)
            nativeViewModel.isReadOnly = false
            #if os(iOS)
            onFormattingBarPresentationChange?(resolvedFormattingBarPresentation)
            #endif
        }
        .onDisappear {
            editorViewModel.detachNativeEditor(nativeViewModel)
        }
        .onChange(of: editorViewModel.currentNoteId) { _, _ in
            nativeViewModel.setBaseFontSize(editorBaseFontSize)
            loadIfNeeded()
        }
        .onChange(of: nativeViewModel.hasUnsavedChanges) { _, hasChanges in
            DispatchQueue.main.async {
                editorViewModel.setDirty(hasChanges)
            }
        }
        .onChange(of: nativeViewModel.autosaveToken) { _, _ in
            guard nativeViewModel.hasUnsavedChanges else { return }
            Task {
                await editorViewModel.syncFromNativeEditor(nativeViewModel)
            }
        }
        .onChange(of: environment.isOffline) { _, isOffline in
            applyAutosaveDelay(isOffline: isOffline)
        }
        .onChange(of: appTextSizeRaw) { _, newValue in
            let option = AppTextSizeOption.resolved(from: newValue)
            nativeViewModel.setBaseFontSize(NoteTextTypography.defaultBodyFontSize(for: option))
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isSoftwareKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isSoftwareKeyboardVisible = false
        }
        .onChange(of: resolvedFormattingBarPresentation) { _, newValue in
            onFormattingBarPresentationChange?(newValue)
        }
        #endif
        .onKeyPress(.escape) {
            handleEscapeKey(document: nativeViewModel.currentPersistenceSnapshot().document)
        }
    }

    @ViewBuilder
    private var editorSurface: some View {
        platformEditorSurface
    }

    static var preferredEditorSurfaceKind: EditorSurfaceKind {
        #if os(iOS)
        .uiKit
        #else
        .appKit
        #endif
    }

    private var editorBaseFontSize: CGFloat {
        let option = AppTextSizeOption.resolved(from: appTextSizeRaw)
        return NoteTextTypography.defaultBodyFontSize(for: option)
    }

    static func loadNoteIfNeeded(
        editorViewModel: NotesEditorViewModel,
        nativeViewModel: NativeNoteEditorViewModel,
        loadedNoteId: String?
    ) -> String? {
        guard let noteId = editorViewModel.currentNoteId else { return loadedNoteId }
        guard noteId != loadedNoteId else { return loadedNoteId }

        nativeViewModel.loadDocument(
            canonicalContent: editorViewModel.canonicalContent,
            plainText: editorViewModel.content
        )
        if let pendingSelectionTarget = editorViewModel.pendingEditSelectionTargetForCurrentEditSession() {
            nativeViewModel.applySelectionTarget(pendingSelectionTarget)
        }

        return noteId
    }

    private func loadIfNeeded() {
        let previousLoadedNoteId = loadedNoteId
        loadedNoteId = Self.loadNoteIfNeeded(
            editorViewModel: editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: loadedNoteId
        )
        if loadedNoteId != previousLoadedNoteId {
            pendingSelectionTarget = editorViewModel.consumePendingEditSelectionTarget()
            pendingSelectionViewportAnchorY = editorViewModel.consumePendingEditViewportAnchorY()
            #if os(iOS)
            NotesIOSDebugTrace.log(
                "AttributedNoteEditorContainer.loadIfNeeded.newNote",
                extras: [
                    "loadedNoteId": loadedNoteId ?? "nil",
                    "pendingSelectionTarget": String(describing: pendingSelectionTarget),
                    "pendingSelectionViewportAnchorY": pendingSelectionViewportAnchorY.map {
                        String(format: "%.2f", $0)
                    } ?? "nil"
                ]
            )
            #endif
        }
    }

    private func applyAutosaveDelay(isOffline: Bool) {
        _ = isOffline
        nativeViewModel.autosaveDelay = 1.5
    }

    func handleEscapeKey(document: NotesSemanticDocument? = nil) -> KeyPress.Result {
        guard editorViewModel.currentNoteId != nil else { return .ignored }
        let resolvedDocument = document ?? nativeViewModel.currentPersistenceSnapshot().document
        #if os(macOS)
        DispatchQueue.main.async {
            onEscape?(resolvedDocument)
        }
        #else
        onEscape?(resolvedDocument)
        #endif
        return .handled
    }

    @ViewBuilder
    private var platformEditorSurface: some View {
        #if os(iOS)
        UIKitNoteTextEditorSurface(
            viewModel: nativeViewModel,
            maxContentWidth: maxContentWidth,
            isEditable: true,
            shouldAutofocus: autofocusEnabled,
            formattingBarConfiguration: editorViewModel.noteFormattingBarConfiguration,
            formattingBarPresentation: resolvedFormattingBarPresentation,
            pendingSelectionTarget: pendingSelectionTarget,
            pendingSelectionViewportAnchorY: pendingSelectionViewportAnchorY,
            onPendingSelectionTargetApplied: { _ in
                pendingSelectionTarget = nil
            },
            onDidBeginEditing: { textView in
                let viewportAnchorY = pendingSelectionViewportAnchorY
                pendingSelectionViewportAnchorY = nil
                NotesIOSDebugTrace.log(
                    "AttributedNoteEditorContainer.onDidBeginEditing",
                    textView: textView,
                    extras: [
                        "viewportAnchorY": viewportAnchorY.map { String(format: "%.2f", $0) } ?? "nil"
                    ]
                )
                guard let viewportAnchorY else {
                    textView.suppressAutofocusReveal = false
                    DispatchQueue.main.async {
                        onInitialPresentationReady?()
                    }
                    return
                }
                NotesIOSDebugTrace.log(
                    "AttributedNoteEditorContainer.onDidBeginEditing.enqueueViewportCorrection",
                    textView: textView,
                    extras: [
                        "viewportAnchorY": String(format: "%.2f", viewportAnchorY)
                    ]
                )
                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    defer { textView.suppressAutofocusReveal = false }
                    NotesIOSDebugTrace.log(
                        "AttributedNoteEditorContainer.onDidBeginEditing.fireViewportCorrection.begin",
                        textView: textView,
                        extras: [
                            "viewportAnchorY": String(format: "%.2f", viewportAnchorY)
                        ]
                    )
                    textView.layoutIfNeeded()
                    textView.positionCurrentSelection(
                        atViewportAnchorY: viewportAnchorY
                    )
                    onInitialPresentationReady?()
                    NotesIOSDebugTrace.log(
                        "AttributedNoteEditorContainer.onDidBeginEditing.fireViewportCorrection.end",
                        textView: textView,
                        extras: [
                            "viewportAnchorY": String(format: "%.2f", viewportAnchorY)
                        ]
                    )
                }
            },
            onViewportOffsetChange: { offset in
                editorViewModel.recordLiveEditorViewportOffset(offset)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
        #else
        AppKitNoteTextEditorSurface(
            viewModel: nativeViewModel,
            maxContentWidth: maxContentWidth,
            isEditable: true,
            shouldAutofocus: autofocusEnabled
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
        #endif
    }

    #if os(iOS)
    private var resolvedFormattingBarPresentation: NoteFormattingBarPresentation {
        return NoteFormattingBarPresentation.resolve(
            isEditing: true,
            isPhone: UIDevice.current.userInterfaceIdiom == .phone,
            isSoftwareKeyboardVisible: isSoftwareKeyboardVisible
        )
    }
    #endif
}

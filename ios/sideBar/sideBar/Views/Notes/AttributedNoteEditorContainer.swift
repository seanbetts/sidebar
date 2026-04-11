import SwiftUI
#if os(iOS)
import Combine
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorContainer: View {
    enum EditorSurfaceKind: Equatable {
        case swiftUI
        case appKit
        case uiKit
    }

    #if os(iOS)
    typealias EditorTextViewFactory = () -> UIKitNoteTextEditorSurface.AccessoryTextView
    #else
    typealias EditorTextViewFactory = () -> AnyObject
    #endif

    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    let autofocusEnabled: Bool
    let onFormattingBarPresentationChange: ((NoteFormattingBarPresentation) -> Void)?
    let onInitialPresentationReady: (() -> Void)?
    let onEscape: ((NotesSemanticDocument) -> Void)?
    let makeTextView: EditorTextViewFactory?
    @EnvironmentObject var environment: AppEnvironment

    @StateObject private var nativeViewModel: NativeNoteEditorViewModel
    @State private var loadedNoteId: String?
    @State private var pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?
    @State private var pendingSelectionViewportOffset: CGPoint?
    @State private var pendingSelectionViewportAnchorY: CGFloat?
    @State private var shouldSkipDidBeginEditingPresentationReady = false
    @State private var pendingPostAutofocusViewportAnchorY: CGFloat?
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
        onEscape: ((NotesSemanticDocument) -> Void)?,
        makeTextView: EditorTextViewFactory? = nil
    ) {
        self.editorViewModel = editorViewModel
        self.maxContentWidth = maxContentWidth
        self.autofocusEnabled = autofocusEnabled
        self.onFormattingBarPresentationChange = onFormattingBarPresentationChange
        self.onInitialPresentationReady = onInitialPresentationReady
        self.onEscape = onEscape
        self.makeTextView = makeTextView
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
            pendingSelectionViewportOffset = editorViewModel.consumePendingEditViewportOffset()
            pendingSelectionViewportAnchorY = editorViewModel.consumePendingEditViewportAnchorY()
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
        if let keyWindow = NSApp.keyWindow,
           keyWindow.firstResponder != nil {
            keyWindow.makeFirstResponder(nil)
        }
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
        let viewportBootstrapTolerance: CGFloat = 6
        UIKitNoteTextEditorSurface(
            viewModel: nativeViewModel,
            maxContentWidth: maxContentWidth,
            isEditable: true,
            shouldAutofocus: autofocusEnabled && editorViewModel.shouldAutofocusEditorSurface,
            formattingBarConfiguration: editorViewModel.noteFormattingBarConfiguration(
                for: nativeViewModel
            ),
            formattingBarPresentation: resolvedFormattingBarPresentation,
            pendingSelectionTarget: pendingSelectionTarget,
            pendingSelectionViewportAnchorY: pendingSelectionViewportAnchorY,
            onPendingSelectionTargetApplied: { _ in
                pendingSelectionTarget = nil
            },
            onDidBeginEditing: { textView in
                editorViewModel.markEditorAutofocusSatisfied()
                if shouldSkipDidBeginEditingPresentationReady {
                    shouldSkipDidBeginEditingPresentationReady = false
                    if let pendingPostAutofocusViewportAnchorY {
                        textView.layoutIfNeeded()
                        textView.positionCurrentSelection(
                            atViewportAnchorY: pendingPostAutofocusViewportAnchorY
                        )
                        self.pendingPostAutofocusViewportAnchorY = nil
                    }
                    textView.suppressAutofocusReveal = false
                    DispatchQueue.main.async {
                        onInitialPresentationReady?()
                    }
                    return
                }
                let viewportAnchorY = pendingSelectionViewportAnchorY
                pendingSelectionViewportAnchorY = nil
                guard let viewportAnchorY else {
                    if pendingSelectionTarget != nil {
                        textView.layoutIfNeeded()
                        textView.scrollCurrentSelectionIntoView()
                    }
                    textView.suppressAutofocusReveal = false
                    if editorViewModel.isHoldingReadSurfaceDuringEditEntry {
                        DispatchQueue.main.async {
                            onInitialPresentationReady?()
                        }
                    }
                    return
                }
                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    defer { textView.suppressAutofocusReveal = false }
                    textView.layoutIfNeeded()
                    textView.positionCurrentSelection(
                        atViewportAnchorY: viewportAnchorY
                    )
                    if editorViewModel.isHoldingReadSurfaceDuringEditEntry {
                        onInitialPresentationReady?()
                    }
                }
            },
            onViewportSnapshotChange: { offset, selectedUTF16Range, selectionViewportAnchorY in
                editorViewModel.recordLiveEditorViewportSnapshot(
                    offset: offset,
                    selectedUTF16Range: selectedUTF16Range,
                    selectionViewportAnchorY: selectionViewportAnchorY
                )
            },
            onTextViewReady: { textView in
                editorViewModel.attachNativeEditorTextView(textView)
                if let pendingSelectionViewportOffset,
                   !textView.isFirstResponder,
                   textView.hasScheduledAutofocus == false {
                    let clampedOffset = UIKitNoteTextEditorSurface.clampedContentOffset(
                        pendingSelectionViewportOffset,
                        for: textView
                    )
                    if abs(textView.contentOffset.x - clampedOffset.x) > 0.5
                        || abs(textView.contentOffset.y - clampedOffset.y) > 0.5 {
                        textView.setContentOffset(clampedOffset, animated: false)
                    }
                }
                guard autofocusEnabled,
                      let viewportAnchorY = pendingSelectionViewportAnchorY,
                      textView.window != nil,
                      !textView.isFirstResponder,
                      !textView.hasScheduledAutofocus else { return }
                textView.suppressAutofocusReveal = true
                textView.hasScheduledAutofocus = true
                defer { textView.hasScheduledAutofocus = false }
                textView.layoutIfNeeded()
                let shouldRepairSelectionAnchor: Bool
                if let currentViewportAnchorY = textView.currentSelectionViewportAnchorY(),
                   pendingSelectionViewportOffset != nil {
                    shouldRepairSelectionAnchor =
                        abs(currentViewportAnchorY - viewportAnchorY) > viewportBootstrapTolerance
                } else {
                    shouldRepairSelectionAnchor = true
                }
                if shouldRepairSelectionAnchor {
                    textView.positionCurrentSelection(atViewportAnchorY: viewportAnchorY)
                }
                pendingPostAutofocusViewportAnchorY = viewportAnchorY
                shouldSkipDidBeginEditingPresentationReady = true
                pendingSelectionViewportOffset = nil
                pendingSelectionViewportAnchorY = nil
                if textView.shouldAutofocus, textView.window != nil, !textView.isFirstResponder {
                    textView.window?.makeKey()
                    _ = textView.becomeFirstResponder()
                }
            },
            makeTextView: makeTextView,
            onEscape: {
                _ = handleEscapeKey(
                    document: nativeViewModel.currentPersistenceSnapshot().document
                )
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
        #else
        AppKitNoteTextEditorSurface(
            viewModel: nativeViewModel,
            maxContentWidth: maxContentWidth,
            isEditable: true,
            shouldAutofocus: autofocusEnabled,
            onEscape: {
                _ = handleEscapeKey(
                    document: nativeViewModel.currentPersistenceSnapshot().document
                )
            }
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

import SwiftUI
#if os(iOS)
import Combine
import UIKit
#endif

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorContainer: View {
    enum EditorSurfaceKind: Equatable {
        case swiftUI
        case uiKit
    }

    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    let autofocusEnabled: Bool
    let onFormattingBarPresentationChange: ((NoteFormattingBarPresentation) -> Void)?
    let onEscape: ((NotesSemanticDocument) -> Void)?
    @EnvironmentObject var environment: AppEnvironment

    @StateObject private var nativeViewModel: NativeNoteEditorViewModel
    @State private var loadedNoteId: String?
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue
    #if os(iOS)
    @State private var isSoftwareKeyboardVisible = false
    #endif

    init(
        editorViewModel: NotesEditorViewModel,
        maxContentWidth: CGFloat,
        autofocusEnabled: Bool = true,
        onFormattingBarPresentationChange: ((NoteFormattingBarPresentation) -> Void)? = nil,
        onEscape: ((NotesSemanticDocument) -> Void)?
    ) {
        self.editorViewModel = editorViewModel
        self.maxContentWidth = maxContentWidth
        self.autofocusEnabled = autofocusEnabled
        self.onFormattingBarPresentationChange = onFormattingBarPresentationChange
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
        .swiftUI
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

        if let target = editorViewModel.consumePendingEditSelectionTarget() {
            nativeViewModel.applySelectionTarget(target)
        }

        return noteId
    }

    private func loadIfNeeded() {
        loadedNoteId = Self.loadNoteIfNeeded(
            editorViewModel: editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: loadedNoteId
        )
    }

    private func applyAutosaveDelay(isOffline: Bool) {
        _ = isOffline
        nativeViewModel.autosaveDelay = 1.5
    }

    func handleEscapeKey(document: NotesSemanticDocument? = nil) -> KeyPress.Result {
        guard editorViewModel.currentNoteId != nil else { return .ignored }
        onEscape?(document ?? nativeViewModel.currentPersistenceSnapshot().document)
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
            formattingBarPresentation: resolvedFormattingBarPresentation
        )
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
        #else
        SwiftUINoteTextEditorSurface(
            viewModel: nativeViewModel,
            maxContentWidth: maxContentWidth,
            isEditable: true
        )
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

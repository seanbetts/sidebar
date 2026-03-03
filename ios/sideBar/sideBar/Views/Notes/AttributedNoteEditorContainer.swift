import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorContainer: View {
    @ObservedObject var editorViewModel: NotesEditorViewModel
    let maxContentWidth: CGFloat
    @EnvironmentObject var environment: AppEnvironment

    @StateObject private var nativeViewModel = NativeNoteEditorViewModel()
    @State private var loadedNoteId: String?
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    var body: some View {
        VStack(spacing: 0) {
            AttributedNoteEditorView(
                viewModel: nativeViewModel,
                maxContentWidth: maxContentWidth,
                isEditable: true,
                onTap: nil
            )
        }
        .onAppear {
            nativeViewModel.setBaseFontSize(editorBaseFontSize)
            editorViewModel.attachNativeEditor(nativeViewModel)
            loadIfNeeded()
            applyAutosaveDelay(isOffline: environment.isOffline)
            nativeViewModel.isReadOnly = false
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
        .onKeyPress(.escape) {
            guard editorViewModel.currentNoteId != nil else { return .ignored }
            environment.emitShortcutAction(.closeItem)
            return .handled
        }
    }

    private var editorBaseFontSize: CGFloat {
        let option = AppTextSizeOption.resolved(from: appTextSizeRaw)
        return NoteTextTypography.defaultBodyFontSize(for: option)
    }

    private func loadIfNeeded() {
        guard let noteId = editorViewModel.currentNoteId else { return }
        guard noteId != loadedNoteId else { return }
        loadedNoteId = noteId
        nativeViewModel.loadDocument(
            canonicalContent: editorViewModel.canonicalContent,
            plainText: editorViewModel.content
        )
    }

    private func applyAutosaveDelay(isOffline: Bool) {
        _ = isOffline
        nativeViewModel.autosaveDelay = 1.5
    }
}

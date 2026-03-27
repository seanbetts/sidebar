import SwiftUI

extension NotesEditorViewModel {
    @available(iOS 26.0, macOS 26.0, *)
    func finalizeNativeEditorMutation(
        _ nativeEditorViewModel: NativeNoteEditorViewModel,
        previousContent: AttributedString,
        previousSelection: AttributedTextSelection
    ) {
        guard nativeEditorViewModel.attributedContent != previousContent
            || nativeEditorViewModel.selection != previousSelection else {
            return
        }
        nativeEditorViewModel.requestViewportPreservationOnNextProgrammaticRender()
        if !nativeEditorViewModel.hasUnsavedChanges {
            nativeEditorViewModel.hasUnsavedChanges = true
        }
        nativeEditorViewModel.scheduleAutosave()
        nativeEditorViewModel.lastSelectionLineSpan = nativeEditorViewModel.selectionLineSpan(
            in: nativeEditorViewModel.attributedContent
        )
        setDirty(true)
    }
}

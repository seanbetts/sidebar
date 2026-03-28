#if os(macOS)
import AppKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func mountedStructuralEditorSnapshot(
    from textView: NSTextView
) -> NativeNoteEditorViewModel.PersistenceSnapshot? {
    (textView.delegate as? AppKitNoteTextEditorSurface.Coordinator)?.viewModel.currentPersistenceSnapshot()
}
#endif

import Foundation
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func serializedNoteContent(_ viewModel: NativeNoteEditorViewModel) -> String {
    var exportContent = viewModel.attributedContent
    let selection = viewModel.selectionSnapshot(in: exportContent)
    _ = viewModel.removeInjectedListMarkers(in: &exportContent, selection: selection)
    let constrained = NoteTextFormattingDefinition().constrainedDocument(exportContent)
    return NoteTextExporter().markdown(from: constrained, frontmatter: viewModel.frontmatter)
}

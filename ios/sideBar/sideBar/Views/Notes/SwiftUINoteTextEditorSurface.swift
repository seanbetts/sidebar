import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct SwiftUINoteTextEditorSurface: View {
    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $viewModel.attributedContent, selection: $viewModel.selection)
            .attributedTextFormattingDefinition(
                NoteTextFormattingDefinition(baseFontSize: viewModel.baseFontSize)
            )
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .disabled(!isEditable)
            .padding(.horizontal, NoteTextLayout.horizontalPadding)
            .padding(.vertical, NoteTextLayout.verticalPadding)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Colors.background)
            .onAppear {
                guard isEditable else { return }
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
            .onChange(of: isEditable) { _, editable in
                guard editable else { return }
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
            .onChange(of: viewModel.attributedContent) { previous, current in
                guard viewModel.isReadOnly == false else { return }
                guard previous != current else { return }
                DispatchQueue.main.async {
                    viewModel.handleContentChange(previous: previous)
                }
            }
            .onChange(of: viewModel.selection) { _, _ in
                guard viewModel.isReadOnly == false else { return }
                DispatchQueue.main.async {
                    viewModel.handleSelectionChange()
                }
            }
    }
}

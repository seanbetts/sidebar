import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct NativeMarkdownEditorView: View {
    @ObservedObject var viewModel: NativeMarkdownEditorViewModel
    let maxContentWidth: CGFloat
    let onSave: (String) -> Void

    public init(
        viewModel: NativeMarkdownEditorViewModel,
        maxContentWidth: CGFloat,
        onSave: @escaping (String) -> Void
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $viewModel.attributedContent, selection: $viewModel.selection)
                .attributedTextFormattingDefinition(MarkdownFormattingDefinition())
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(
                    EdgeInsets(
                        top: DesignTokens.Spacing.md,
                        leading: DesignTokens.Spacing.lg,
                        bottom: DesignTokens.Spacing.md,
                        trailing: DesignTokens.Spacing.lg
                    )
                )
                .onChange(of: viewModel.attributedContent) { oldValue, _ in
                    viewModel.handleContentChange(previous: oldValue)
                }
        }
        .background(DesignTokens.Colors.background)
    }
}

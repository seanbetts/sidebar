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
        TextEditor(text: $viewModel.attributedContent, selection: $viewModel.selection)
            .attributedTextFormattingDefinition(MarkdownFormattingDefinition())
            .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
            .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: viewModel.attributedContent) { oldValue, _ in
                viewModel.handleContentChange(previous: oldValue)
            }
            .onChange(of: viewModel.selection) { _, _ in
                viewModel.handleSelectionChange()
            }
            .background(DesignTokens.Colors.background)
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownReadOnlyView: View {
    let attributedContent: AttributedString
    let maxContentWidth: CGFloat

    var body: some View {
        ScrollView {
            Text(attributedContent)
                .textSelection(.enabled)
                .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
                .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
    }
}

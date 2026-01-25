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
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                blockMenu
            }
        }
        #endif
    }

    private var blockMenu: some View {
        Menu {
            Button("Heading 1") { viewModel.applyHeading(level: 1) }
            Button("Heading 2") { viewModel.applyHeading(level: 2) }
            Button("Heading 3") { viewModel.applyHeading(level: 3) }
            Divider()
            Button("Bulleted list") { viewModel.applyList(ordered: false) }
            Button("Numbered list") { viewModel.applyList(ordered: true) }
            Button("Task") { viewModel.applyTask() }
            Divider()
            Button("Quote") { viewModel.applyQuote() }
            Button("Code block") { viewModel.applyCodeBlock(language: nil) }
        } label: {
            Image(systemName: "textformat")
        }
    }
}

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
            if !viewModel.isReadOnly {
                formattingToolbar
            }

            ScrollView {
                TextEditor(text: $viewModel.attributedContent, selection: $viewModel.selection)
                    .formattingDefinition(MarkdownFormattingDefinition())
                    .scrollDisabled(true)
                    .frame(maxWidth: maxContentWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .onChange(of: viewModel.attributedContent) { oldValue, _ in
                        viewModel.handleContentChange(previous: oldValue)
                    }
            }
        }
        .background(DesignTokens.Colors.background)
    }

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                toolbarButton(systemImage: "bold") {
                    viewModel.applyFormatting(.bold)
                }
                toolbarButton(systemImage: "italic") {
                    viewModel.applyFormatting(.italic)
                }
                toolbarButton(systemImage: "strikethrough") {
                    viewModel.applyFormatting(.strikethrough)
                }
                toolbarButton(systemImage: "chevron.left.slash.chevron.right") {
                    viewModel.applyFormatting(.inlineCode)
                }

                Divider()
                    .frame(height: 20)

                toolbarButton(systemImage: "list.bullet") {
                    viewModel.applyFormatting(.bulletList)
                }
                toolbarButton(systemImage: "list.number") {
                    viewModel.applyFormatting(.orderedList)
                }
                toolbarButton(systemImage: "checkmark.square") {
                    viewModel.applyFormatting(.taskList)
                }

                Divider()
                    .frame(height: 20)

                toolbarButton(systemImage: "text.quote") {
                    viewModel.applyFormatting(.blockquote)
                }
                toolbarButton(systemImage: "link") {
                    if let url = URL(string: "https://") {
                        viewModel.applyFormatting(.link(url))
                    }
                }
                toolbarButton(systemImage: "minus") {
                    viewModel.applyFormatting(.horizontalRule)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .background(DesignTokens.Colors.surface)
    }

    private func toolbarButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

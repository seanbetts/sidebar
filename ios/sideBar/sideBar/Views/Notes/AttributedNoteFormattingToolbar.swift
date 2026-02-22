import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteFormattingToolbar: View {
    @ObservedObject var viewModel: NativeMarkdownEditorViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                toolbarButton(
                    title: "Bold",
                    systemImage: "bold",
                    isActive: viewModel.isBoldActive()
                ) {
                    viewModel.applyFormatting(.bold)
                }
                toolbarButton(
                    title: "Italic",
                    systemImage: "italic",
                    isActive: viewModel.isItalicActive()
                ) {
                    viewModel.applyFormatting(.italic)
                }
                toolbarButton(
                    title: "Strike",
                    systemImage: "strikethrough"
                ) {
                    viewModel.applyFormatting(.strikethrough)
                }
                toolbarButton(
                    title: "Code",
                    systemImage: "chevron.left.slash.chevron.right"
                ) {
                    viewModel.applyFormatting(.inlineCode)
                }
                toolbarButton(
                    title: "Heading",
                    systemImage: "textformat.size"
                ) {
                    viewModel.applyFormatting(.heading(level: 2))
                }
                toolbarButton(
                    title: "Bullets",
                    systemImage: "list.bullet"
                ) {
                    viewModel.applyFormatting(.bulletList)
                }
                toolbarButton(
                    title: "Numbers",
                    systemImage: "list.number"
                ) {
                    viewModel.applyFormatting(.orderedList)
                }
                toolbarButton(
                    title: "Tasks",
                    systemImage: "checklist"
                ) {
                    viewModel.applyFormatting(.taskList)
                }
                toolbarButton(
                    title: "Quote",
                    systemImage: "text.quote"
                ) {
                    viewModel.applyFormatting(.blockquote)
                }
                toolbarButton(
                    title: "Code Block",
                    systemImage: "curlybraces.square"
                ) {
                    viewModel.applyFormatting(.codeBlock)
                }
                toolbarButton(
                    title: "Rule",
                    systemImage: "minus"
                ) {
                    viewModel.applyFormatting(.horizontalRule)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .background(DesignTokens.Colors.background)
    }

    @ViewBuilder
    private func toolbarButton(
        title: String,
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : DesignTokens.Colors.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.14) : DesignTokens.Colors.muted)
        )
        .accessibilityLabel(title)
        .disabled(viewModel.isReadOnly)
    }
}

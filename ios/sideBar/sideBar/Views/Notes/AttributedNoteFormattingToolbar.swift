import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteFormattingToolbar: View {
    @ObservedObject var viewModel: NativeNoteEditorViewModel

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
                    systemImage: "strikethrough",
                    isActive: viewModel.isStrikethroughActive()
                ) {
                    viewModel.applyFormatting(.strikethrough)
                }
                toolbarButton(
                    title: "Code",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    isActive: viewModel.isInlineCodeActive()
                ) {
                    viewModel.applyFormatting(.inlineCode)
                }
                toolbarButton(
                    title: "Demote heading",
                    systemImage: "textformat.size.smaller",
                    isActive: viewModel.isHeadingActive()
                ) {
                    viewModel.applyFormatting(.demoteHeading)
                }
                textSizeIndicator
                toolbarButton(
                    title: "Promote heading",
                    systemImage: "textformat.size.larger",
                    isActive: viewModel.isHeadingActive()
                ) {
                    viewModel.applyFormatting(.promoteHeading)
                }
                toolbarButton(
                    title: "Bullets",
                    systemImage: "list.bullet",
                    isActive: viewModel.isBlockKindActive(.bulletList)
                ) {
                    viewModel.applyFormatting(.bulletList)
                }
                toolbarButton(
                    title: "Numbers",
                    systemImage: "list.number",
                    isActive: viewModel.isBlockKindActive(.orderedList)
                ) {
                    viewModel.applyFormatting(.orderedList)
                }
                toolbarButton(
                    title: "Tasks",
                    systemImage: "checklist",
                    isActive: viewModel.isTaskListActive()
                ) {
                    viewModel.applyFormatting(.taskList)
                }
                toolbarButton(
                    title: "Quote",
                    systemImage: "text.quote",
                    isActive: viewModel.isBlockKindActive(.blockquote)
                ) {
                    viewModel.applyFormatting(.blockquote)
                }
                toolbarButton(
                    title: "Code Block",
                    systemImage: "curlybraces",
                    isActive: viewModel.isBlockKindActive(.codeBlock)
                ) {
                    viewModel.applyFormatting(.codeBlock)
                }
                codeLanguageMenu
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

    private var codeLanguageMenu: some View {
        Menu {
            Button("No language") {
                viewModel.applyCodeBlock(language: nil)
            }
            Divider()
            ForEach(codeLanguageOptions, id: \.value) { option in
                Button(option.label) {
                    viewModel.applyCodeBlock(language: option.value)
                }
            }
        } label: {
            Image(systemName: "tag")
                .appScaledFont(size: 14, weight: .regular)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(DesignTokens.Colors.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignTokens.Colors.muted)
        )
        .accessibilityLabel("Code language")
        .disabled(viewModel.isReadOnly)
    }

    private var textSizeIndicator: some View {
        Text(viewModel.currentTextSizeDisplay())
            .appScaledFont(size: 12, weight: .semibold)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignTokens.Colors.muted)
            )
            .accessibilityLabel("Current text size \(viewModel.currentTextSizeDisplay())")
    }

    @ViewBuilder
    private func toolbarButton(
        title: String,
        systemImage: String,
        isActive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .appScaledFont(size: 14, weight: isActive ? .semibold : .regular)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : DesignTokens.Colors.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.14) : DesignTokens.Colors.muted)
        )
        .accessibilityLabel(title)
        .disabled(viewModel.isReadOnly || isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var codeLanguageOptions: [(label: String, value: String)] {
        [
            ("Swift", "swift"),
            ("TypeScript", "typescript"),
            ("JavaScript", "javascript"),
            ("Python", "python"),
            ("JSON", "json"),
            ("SQL", "sql"),
            ("Bash", "bash")
        ]
    }
}

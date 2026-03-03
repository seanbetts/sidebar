import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteFormattingToolbar: View {
    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let enabledCapabilities: Set<NoteFormattingCapability>

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if enabledCapabilities.contains(.bold) {
                toolbarButton(
                    title: "Bold",
                    systemImage: "bold",
                    isActive: viewModel.isBoldActive()
                ) {
                    applyFormatting(.bold)
                }
            }
            if enabledCapabilities.contains(.italic) {
                toolbarButton(
                    title: "Italic",
                    systemImage: "italic",
                    isActive: viewModel.isItalicActive()
                ) {
                    applyFormatting(.italic)
                }
            }
            if enabledCapabilities.contains(.underline) {
                toolbarButton(
                    title: "Underline",
                    systemImage: "underline",
                    isActive: viewModel.isUnderlineActive()
                ) {
                    applyFormatting(.underline)
                }
            }
            if enabledCapabilities.contains(.bulletList) {
                toolbarButton(
                    title: "Bullets",
                    systemImage: "list.bullet",
                    isActive: viewModel.isBlockKindActive(.bulletList)
                ) {
                    applyFormatting(.bulletList)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.background)
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        isActive: Bool,
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
        .disabled(viewModel.isReadOnly)
    }

    private func applyFormatting(_ formatting: NoteFormatting) {
        viewModel.applyFormatting(formatting)
    }
}

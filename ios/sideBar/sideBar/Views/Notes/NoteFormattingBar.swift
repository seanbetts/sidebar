import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
struct NoteFormattingBar: View {
    let isBoldActive: Bool
    let isItalicActive: Bool
    let isUnderlineActive: Bool
    let isStrikethroughActive: Bool
    let onBoldTap: @MainActor @Sendable () -> Void
    let onItalicTap: @MainActor @Sendable () -> Void
    let onUnderlineTap: @MainActor @Sendable () -> Void
    let onStrikethroughTap: @MainActor @Sendable () -> Void

    var body: some View {
        HStack(spacing: 10) {
            formattingButton(
                systemImage: "bold",
                label: "Bold",
                isActive: isBoldActive,
                action: onBoldTap
            )
            formattingButton(
                systemImage: "italic",
                label: "Italic",
                isActive: isItalicActive,
                action: onItalicTap
            )
            formattingButton(
                systemImage: "underline",
                label: "Underline",
                isActive: isUnderlineActive,
                action: onUnderlineTap
            )
            formattingButton(
                systemImage: "strikethrough",
                label: "Strikethrough",
                isActive: isStrikethroughActive,
                action: onStrikethroughTap
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .accessibilityIdentifier("note-formatting-bar")
    }

    @ViewBuilder
    private func formattingButton(
        systemImage: String,
        label: String,
        isActive: Bool,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("note-formatting-\(label.lowercased())")
    }
}

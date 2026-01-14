import SwiftUI

struct MarkdownFormattingToolbar: View {
    let isReadOnly: Bool
    let onCommand: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                toolbarButton("bold", systemImage: "bold", label: "Bold")
                toolbarButton("italic", systemImage: "italic", label: "Italic")
                toolbarButton("strike", systemImage: "strikethrough", label: "Strikethrough")
                toolbarButton("inlineCode", systemImage: "chevron.left.slash.chevron.right", label: "Inline code")
                toolbarDivider()
                textButton("H1", command: "heading1")
                textButton("H2", command: "heading2")
                textButton("H3", command: "heading3")
                toolbarDivider()
                toolbarButton("bulletList", systemImage: "list.bullet", label: "Bullet list")
                toolbarButton("orderedList", systemImage: "list.number", label: "Numbered list")
                toolbarButton("taskList", systemImage: "checkmark.square", label: "Task list")
                toolbarDivider()
                toolbarButton("blockquote", systemImage: "text.quote", label: "Blockquote")
                toolbarButton("hr", systemImage: "minus", label: "Horizontal rule")
                toolbarDivider()
                toolbarButton("link", systemImage: "link", label: "Link")
                toolbarButton("codeBlock", systemImage: "chevron.left.slash.chevron.right", label: "Code block")
                toolbarButton("table", systemImage: "tablecells", label: "Table")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .disabled(isReadOnly)
        .opacity(isReadOnly ? 0.4 : 1)
    }

    @ViewBuilder
    private func toolbarButton(_ command: String, systemImage: String, label: String) -> some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func textButton(_ title: String, command: String) -> some View {
        Button {
            onCommand(command)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func toolbarDivider() -> some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }
}

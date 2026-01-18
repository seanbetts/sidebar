import SwiftUI

struct MarkdownFormattingToolbar: View {
    let isReadOnly: Bool
    let onClose: () -> Void
    let onCommand: (String) -> Void
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isCompact {
                    compactToolbar
                } else {
                    fullToolbar
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(isReadOnly)
            .opacity(isReadOnly ? 0.4 : 1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close editor")
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(toolbarBackgroundColor)
        .overlay(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact || availableWidth < 560
        #endif
    }

    private var toolbarBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(.secondarySystemBackground)
        #endif
    }

    private var compactToolbar: some View {
        HStack(spacing: 12) {
            toolbarButton("bold", systemImage: "bold", label: "Bold")
            toolbarButton("italic", systemImage: "italic", label: "Italic")
            toolbarButton("bulletList", systemImage: "list.bullet", label: "Bullet list")
            toolbarButton("taskList", systemImage: "checkmark.square", label: "Task list")
            toolbarButton("link", systemImage: "link", label: "Link")
            toolbarButton("codeBlock", systemImage: "chevron.left.slash.chevron.right", label: "Code block")
            #if os(iOS)
            UIKitMenuButton(
                systemImage: "ellipsis.circle",
                accessibilityLabel: "More formatting",
                items: [
                    MenuActionItem(title: "Strikethrough", systemImage: nil, role: nil) { onCommand("strike") },
                    MenuActionItem(title: "Inline code", systemImage: nil, role: nil) { onCommand("inlineCode") },
                    MenuActionItem(title: "Numbered list", systemImage: nil, role: nil) { onCommand("orderedList") },
                    MenuActionItem(title: "Blockquote", systemImage: nil, role: nil) { onCommand("blockquote") },
                    MenuActionItem(title: "Horizontal rule", systemImage: nil, role: nil) { onCommand("hr") },
                    MenuActionItem(title: "Table", systemImage: nil, role: nil) { onCommand("table") }
                ]
            )
            .frame(width: 28, height: 28)
            #else
            Menu {
                Button("Strikethrough") { onCommand("strike") }
                Button("Inline code") { onCommand("inlineCode") }
                Button("Numbered list") { onCommand("orderedList") }
                Button("Blockquote") { onCommand("blockquote") }
                Button("Horizontal rule") { onCommand("hr") }
                Button("Table") { onCommand("table") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More formatting")
            #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var fullToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                toolbarButton("bold", systemImage: "bold", label: "Bold")
                toolbarButton("italic", systemImage: "italic", label: "Italic")
                toolbarButton("strike", systemImage: "strikethrough", label: "Strikethrough")
                toolbarButton("inlineCode", systemImage: "chevron.left.slash.chevron.right", label: "Inline code")
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
            .fill(toolbarDividerColor)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }

    private var toolbarDividerColor: Color {
        #if os(macOS)
        return Color(NSColor.separatorColor)
        #else
        return Color(.separator)
        #endif
    }
}

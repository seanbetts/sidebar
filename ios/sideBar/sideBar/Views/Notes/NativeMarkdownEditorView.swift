import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct NativeMarkdownEditorView: View {
    @ObservedObject var viewModel: NativeMarkdownEditorViewModel
    let maxContentWidth: CGFloat
    let onSave: (String) -> Void
    @State private var isLinkPromptPresented = false
    @State private var linkValue = "https://"

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
            ScrollView {
                TextEditor(text: $viewModel.attributedContent, selection: $viewModel.selection)
                    .attributedTextFormattingDefinition(\.markdownEditor)
                    .scrollDisabled(true)
                    .frame(maxWidth: maxContentWidth)
                    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
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
        }
        .background(DesignTokens.Colors.background)
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Toggle(isOn: boldBinding) {
                    Image(systemName: "bold")
                }
                Toggle(isOn: italicBinding) {
                    Image(systemName: "italic")
                }
                Button {
                    viewModel.toggleInlineCode()
                } label: {
                    Image(systemName: "chevron.left.slash.chevron.right")
                }
                Button {
                    isLinkPromptPresented = true
                } label: {
                    Image(systemName: "link")
                }

                Spacer()

                blockMenu
            }
        }
        #endif
        .alert("Insert Link", isPresented: $isLinkPromptPresented) {
            TextField("https://", text: $linkValue)
            Button("Insert") {
                let trimmed = linkValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: trimmed) {
                    viewModel.applyLink(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apply a URL to the current selection.")
        }
    }

    private var boldBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isBoldActive() },
            set: { enabled in
                viewModel.setBold(enabled)
            }
        )
    }

    private var italicBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isItalicActive() },
            set: { enabled in
                viewModel.setItalic(enabled)
            }
        )
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

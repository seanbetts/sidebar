import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteEditorView: View {
    @ObservedObject var viewModel: NativeMarkdownEditorViewModel
    let maxContentWidth: CGFloat

    var body: some View {
        TextEditor(text: $viewModel.attributedContent, selection: $viewModel.selection)
            .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
            .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .writingToolsBehavior(.disabled)
            .onChange(of: viewModel.attributedContent) { oldValue, _ in
                viewModel.handleContentChange(previous: oldValue)
            }
            .onChange(of: viewModel.selection) { _, _ in
                viewModel.handleSelectionChange()
            }
            .background(DesignTokens.Colors.background)
            #if os(iOS)
            .background {
                TextEditorFormattingConfigurator()
                    .frame(width: 0, height: 0)
            }
            #endif
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct AttributedNoteReadOnlyView: View {
    let attributedContent: AttributedString
    let maxContentWidth: CGFloat
    let onTap: () -> Void

    var body: some View {
        ScrollView {
            Text(attributedContent)
                .textSelection(.enabled)
                .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
                .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .background(DesignTokens.Colors.background)
    }
}

#if os(iOS)
@available(iOS 26.0, *)
private struct TextEditorFormattingConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let textView = findTextView(near: uiView) else { return }
            textView.allowsEditingTextAttributes = false
            textView.inputAssistantItem.leadingBarButtonGroups = []
            textView.inputAssistantItem.trailingBarButtonGroups = []
            textView.textFormattingConfiguration = UITextFormattingViewController.Configuration(groups: [])
        }
    }

    private func findTextView(near view: UIView) -> UITextView? {
        var current: UIView? = view
        while let node = current {
            if let textView = firstTextView(in: node) {
                return textView
            }
            current = node.superview
        }
        return nil
    }

    private func firstTextView(in root: UIView) -> UITextView? {
        if let textView = root as? UITextView {
            return textView
        }
        for child in root.subviews {
            if let textView = firstTextView(in: child) {
                return textView
            }
        }
        return nil
    }
}
#endif

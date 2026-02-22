import Foundation
import SwiftUI

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
            .onChange(of: viewModel.attributedContent) { oldValue, _ in
                viewModel.handleContentChange(previous: oldValue)
            }
            .onChange(of: viewModel.selection) { _, _ in
                viewModel.handleSelectionChange()
            }
            .background(DesignTokens.Colors.background)
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

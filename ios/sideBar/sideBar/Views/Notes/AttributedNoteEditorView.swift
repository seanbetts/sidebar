import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
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
        NativeReadOnlyMarkdownTextView(
            attributedContent: attributedContent,
            onTap: onTap
        )
        .padding(.horizontal, SideBarMarkdownLayout.horizontalPadding)
        .padding(.vertical, SideBarMarkdownLayout.verticalPadding)
        .frame(maxWidth: maxContentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

#if os(iOS)
@available(iOS 26.0, *)
private struct NativeReadOnlyMarkdownTextView: UIViewRepresentable {
    let attributedContent: AttributedString
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.allowsEditingTextAttributes = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = NSAttributedString(attributedContent)

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tapRecognizer.cancelsTouchesInView = false
        textView.addGestureRecognizer(tapRecognizer)
        context.coordinator.tapRecognizer = tapRecognizer
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onTap = onTap
        let updated = NSAttributedString(attributedContent)
        if !textView.attributedText.isEqual(to: updated) {
            textView.attributedText = updated
        }
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        weak var tapRecognizer: UITapGestureRecognizer?

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap()
        }
    }
}
#elseif os(macOS)
@available(macOS 26.0, *)
private struct NativeReadOnlyMarkdownTextView: NSViewRepresentable {
    let attributedContent: AttributedString
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsImageEditing = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textStorage?.setAttributedString(NSAttributedString(attributedContent))

        let tapRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tapRecognizer.numberOfClicksRequired = 1
        tapRecognizer.delaysPrimaryMouseButtonEvents = false
        textView.addGestureRecognizer(tapRecognizer)
        context.coordinator.tapRecognizer = tapRecognizer

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onTap = onTap
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let updated = NSAttributedString(attributedContent)
        if !textView.attributedString().isEqual(to: updated) {
            textView.textStorage?.setAttributedString(updated)
        }
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        weak var tapRecognizer: NSClickGestureRecognizer?

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap()
        }
    }
}
#endif

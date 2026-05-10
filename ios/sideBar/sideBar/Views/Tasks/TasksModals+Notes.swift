import SwiftUI

enum NotesEditorReturnIntent: Equatable {
    case insertNewline
    case submit
}

func notesEditorReturnIntent(commandPressed: Bool) -> NotesEditorReturnIntent {
    commandPressed ? .submit : .insertNewline
}

struct NotesSheet: View {
    private static let autosaveDelayNanoseconds: UInt64 = 1_200_000_000

    let task: TaskItem
    let notes: String
    let onSave: (String) -> Void
    let onAutosave: (String) -> Void
    let onDismiss: () -> Void

    @State private var value: String = ""
    @State private var lastSubmittedValue: String = ""
    @State private var hasLoadedInitialValue: Bool = false
    @State private var autosaveTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        let content = NavigationStack {
            ZStack(alignment: .topLeading) {
                if value.isEmpty {
                    Text("Notes")
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                }
                NotesTextEditor(
                    text: $value,
                    isFocused: Binding(
                        get: { isFocused },
                        set: { isFocused = $0 }
                    ),
                    onSubmit: handleSave
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Notes")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        handleSave()
                    }
                }
            }
            .onAppear {
                value = notes
                lastSubmittedValue = notes
                hasLoadedInitialValue = true
                isFocused = true
            }
            .onChange(of: value) { _, _ in
                guard hasLoadedInitialValue else { return }
                scheduleAutosave()
            }
            .onDisappear {
                autosaveTask?.cancel()
                submitAutosaveIfNeeded()
            }
        }
        #if os(macOS)
        MacModalShell(type: taskNotesMacPanelType()) {
            content
        }
        #else
        content
        #endif
    }

    private func handleSave() {
        autosaveTask?.cancel()
        if value != lastSubmittedValue {
            lastSubmittedValue = value
            onSave(value)
        }
        onDismiss()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.autosaveDelayNanoseconds)
            guard !Task.isCancelled else { return }
            submitAutosaveIfNeeded()
        }
    }

    private func submitAutosaveIfNeeded() {
        guard value != lastSubmittedValue else { return }
        lastSubmittedValue = value
        onAutosave(value)
    }
}

#if os(macOS)
import AppKit

private struct NotesTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NotesTextView()
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NotesTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onSubmit = onSubmit
        if isFocused, nsView.window != nil, nsView.window?.firstResponder != textView {
            nsView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: NotesTextEditor

        init(parent: NotesTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.isFocused = textView.window?.firstResponder == textView
        }
    }
}

private final class NotesTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturnKey = event.keyCode == 36 || event.keyCode == 76
        if isReturnKey {
            switch notesEditorReturnIntent(commandPressed: event.modifierFlags.contains(.command)) {
            case .insertNewline:
                insertNewline(nil)
            case .submit:
                onSubmit?()
            }
            return
        }
        super.keyDown(with: event)
    }
}
#else
import UIKit

private struct NotesTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> NotesTextView {
        let textView = NotesTextView()
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        return textView
    }

    func updateUIView(_ uiView: NotesTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.onSubmit = onSubmit
        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: NotesTextEditor

        init(parent: NotesTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            true
        }
    }
}

private final class NotesTextView: UITextView {
    var onSubmit: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\r", modifierFlags: [.command], action: #selector(handleCommandReturn))
        ]
    }

    @objc private func handleCommandReturn() {
        if notesEditorReturnIntent(commandPressed: true) == .submit {
            onSubmit?()
        }
    }
}
#endif

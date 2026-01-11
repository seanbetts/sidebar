import SwiftUI
import MarkdownUI

public struct ScratchpadPopoverView: View {
    @StateObject private var viewModel: ScratchpadViewModel
    @State private var draft: String = ""
    @State private var headingPrefix: String?
    @State private var isEditing = false
    @State private var isSaving: Bool = false
    @State private var hasLoaded = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isEditorFocused: Bool

    public init(api: any ScratchpadProviding, cache: CacheClient) {
        _viewModel = StateObject(wrappedValue: ScratchpadViewModel(api: api, cache: cache))
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("✏️ Scratchpad")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Group {
                    if isEditing {
                        TextEditor(text: $draft)
                            .font(.body)
                            .focused($isEditorFocused)
                            .accessibilityLabel("Scratchpad text")
                            .accessibilityHint("Enter notes for your scratchpad.")
                    } else {
                        ScrollView {
                            SideBarMarkdown(text: draft.isEmpty ? "_Start typing to capture thoughts._" : draft)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .onTapGesture {
                            isEditing = true
                            isEditorFocused = true
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .onChange(of: draft) { _, _ in
            scheduleSave()
        }
        .onChange(of: isEditorFocused) { _, isFocused in
            if !isFocused {
                isEditing = false
            }
        }
        .task {
            await viewModel.load()
            let content = viewModel.scratchpad?.content ?? ""
            let stripped = stripHeading(from: content)
            headingPrefix = stripped.heading
            draft = stripped.content
            hasLoaded = true
        }
    }

    private func scheduleSave() {
        guard hasLoaded else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await saveDraft()
        }
    }

    private func saveDraft() async {
        guard !isSaving else { return }
        isSaving = true
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String
        if let headingPrefix {
            payload = trimmed.isEmpty ? headingPrefix : "\(headingPrefix)\n\n\(draft)"
        } else {
            payload = draft
        }
        await viewModel.update(content: payload, mode: .replace)
        isSaving = false
    }

    private func stripHeading(from value: String) -> (heading: String?, content: String) {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.hasPrefix("#") else {
            return (nil, value)
        }
        let headingLine = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = headingLine.lowercased()
        guard normalized == "# scratchpad" || normalized == "# ✏️ scratchpad" else {
            return (nil, value)
        }
        let remainder = lines.dropFirst()
        let stripped = remainder.drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .joined(separator: "\n")
        return (headingLine, stripped)
    }
}

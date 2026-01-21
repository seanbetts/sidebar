import SwiftUI
import MarkdownUI

public struct ScratchpadPopoverView: View {
    @StateObject private var viewModel: ScratchpadViewModel
    @ObservedObject private var scratchpadStore: ScratchpadStore
    @State private var draft: String = ""
    @State private var isEditing = false
    @State private var isSaving: Bool = false
    @State private var isLoading: Bool = false
    @State private var isUpdatingContent: Bool = false
    @State private var hasUserEdits: Bool = false
    @State private var lastSavedContent: String = ""
    @State private var hasLoaded = false
    @State private var readModeHeight: CGFloat = 0
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isEditorFocused: Bool

    public init(api: any ScratchpadProviding, cache: CacheClient, scratchpadStore: ScratchpadStore) {
        _viewModel = StateObject(wrappedValue: ScratchpadViewModel(api: api, cache: cache))
        _scratchpadStore = ObservedObject(wrappedValue: scratchpadStore)
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                ScratchpadHeaderRow(
                    isSaving: isSaving,
                    errorMessage: viewModel.errorMessage
                )
                Divider()

                Group {
                    if isEditing {
                        TextEditor(text: $draft)
                            .font(.body)
                            .focused($isEditorFocused)
                            .scrollContentBackground(.hidden)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Scratchpad text")
                            .accessibilityHint("Enter notes for your scratchpad.")
                    } else {
                        ScrollView {
                            SideBarMarkdown(
                                text: draft.isEmpty ? ScratchpadConstants.placeholder : draft
                            )
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
                .overlay {
                    if isLoading && !hasLoaded {
                        ProgressView("Loading...")
                    }
                }
            }
            .frame(idealWidth: 450)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
        .onChange(of: draft) { _, _ in
            guard hasLoaded, !isUpdatingContent else { return }
            hasUserEdits = true
            scheduleSave()
        }
        .onChange(of: isEditorFocused) { _, isFocused in
            if !isFocused {
                isEditing = false
            }
        }
        .onReceive(scratchpadStore.$version) { _ in
            refreshScratchpad()
        }
        .onDisappear {
            saveTask?.cancel()
            if hasUserEdits {
                Task {
                    await saveDraftIfNeeded(force: true)
                }
            }
        }
        .task {
            refreshScratchpad()
        }
    }

    @MainActor
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await saveDraftIfNeeded(force: false)
        }
    }

    @MainActor
    private func refreshScratchpad() {
        guard !isLoading else { return }
        isLoading = true
        if !hasLoaded, let cached = viewModel.cachedScratchpad() {
            applyScratchpadContent(cached.content)
            hasLoaded = true
        }
        Task { @MainActor in
            defer { isLoading = false }
            await viewModel.load()
            let content = viewModel.scratchpad?.content ?? ""
            applyScratchpadContent(content)
            hasLoaded = true
        }
    }

    @MainActor
    private func applyScratchpadContent(_ content: String) {
        let stripped = ScratchpadFormatting.stripHeading(content)
        guard stripped != draft else { return }
        isUpdatingContent = true
        hasUserEdits = false
        lastSavedContent = content
        draft = stripped
        isUpdatingContent = false
    }

    @MainActor
    private func saveDraftIfNeeded(force: Bool) async {
        guard !isSaving else { return }
        guard force || hasUserEdits else { return }
        isSaving = true
        let cleaned = ScratchpadFormatting.removeEmptyTaskItems(draft)
        let payload = ScratchpadFormatting.withHeading(cleaned)
        if payload != lastSavedContent {
            await viewModel.update(content: payload, mode: .replace)
            if viewModel.errorMessage == nil {
                lastSavedContent = payload
                hasUserEdits = false
            }
        }
        isSaving = false
    }
}

private struct ScratchpadHeaderRow: View {
    let isSaving: Bool
    let errorMessage: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(ScratchpadConstants.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            if isSaving {
                statusText("Saving...", color: .secondary)
            } else if let errorMessage {
                statusText(errorMessage, color: .red)
            }
        }
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private struct ScratchpadContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

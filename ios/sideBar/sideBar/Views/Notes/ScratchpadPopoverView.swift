import SwiftUI

public struct ScratchpadPopoverView: View {
    @StateObject private var viewModel: ScratchpadViewModel
    @State private var draft: String = ""
    @State private var isEditing = false
    @State private var isSaving: Bool = false
    @State private var isLoading: Bool = false
    @State private var isUpdatingContent: Bool = false
    @State private var suppressNextDraftChange = false
    @State private var hasUserEdits: Bool = false
    @State private var lastSavedContent: String = ""
    @State private var hasLoaded = false
    @State private var readModeHeight: CGFloat = 0
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isEditorFocused: Bool

    public init(api: any ScratchpadProviding, cache: CacheClient, scratchpadStore: ScratchpadStore) {
        _viewModel = StateObject(
            wrappedValue: ScratchpadViewModel(
                api: api,
                cache: cache,
                scratchpadStore: scratchpadStore
            )
        )
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
                            .appFont(.body)
                            .focused($isEditorFocused)
                            .scrollContentBackground(.hidden)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Scratchpad text")
                            .accessibilityHint("Enter notes for your scratchpad.")
                    } else {
                        ScrollView {
                            Text(draft.isEmpty ? ScratchpadConstants.placeholder : draft)
                                .appFont(.body)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
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
                        VStack(spacing: 8) {
                            LoadingIndicatorView(size: LoadingIndicatorSize.panel)
                            Text("Loading...")
                                .appFont(.caption)
                        }
                    }
                }
            }
            .frame(minHeight: 280)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onChange(of: draft) { _, _ in
            guard hasLoaded, !isUpdatingContent else { return }
            if suppressNextDraftChange {
                suppressNextDraftChange = false
                return
            }
            hasUserEdits = true
            scheduleSave()
        }
        .onChange(of: isEditorFocused) { _, isFocused in
            if !isFocused {
                isEditing = false
            }
        }
        .onChange(of: viewModel.refreshVersion) { _, _ in
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
        suppressNextDraftChange = true
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ScratchpadConstants.title)
                    .appFont(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                if isSaving {
                    statusText("Saving...", color: .secondary)
                }
            }
            if !isSaving, let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .appFont(.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.error)
                        .padding(.top, 1)
                    Text(errorMessage)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .background(DesignTokens.Colors.errorBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous)
                        .stroke(DesignTokens.Colors.errorBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous))
                .accessibilityLabel("Scratchpad error")
                .accessibilityValue(errorMessage)
            }
        }
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .appFont(.caption)
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

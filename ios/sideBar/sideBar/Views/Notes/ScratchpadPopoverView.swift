import sideBarShared
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
        Group {
            if usesPhoneSheetLayout {
                phoneSheetContent
            } else {
                popoverContent
            }
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
            if !isFocused, !usesPhoneSheetLayout {
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

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScratchpadHeaderRow(
                isSaving: isSaving,
                errorMessage: viewModel.errorMessage
            )
            Divider()

            standardScratchpadBody
        }
        .frame(minHeight: 280)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var phoneSheetContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                    ScratchpadErrorBannerView(errorMessage: errorMessage)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.sm)
                }

                VStack(alignment: .leading, spacing: 0) {
                    if isSaving {
                        Text("Saving...")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.top, DesignTokens.Spacing.sm)
                    }

                    phoneScratchpadBody
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .navigationTitle(ScratchpadConstants.title)
            .navigationBarTitleDisplayModeInline()
        }
    }

    @ViewBuilder
    private var phoneScratchpadBody: some View {
        Group {
            if draft.isEmpty && !isEditing {
                scratchpadEmptyState {
                    beginEditing()
                }
            } else {
                TextEditor(text: $draft)
                    .appFont(.body)
                    .focused($isEditorFocused)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Scratchpad text")
                    .accessibilityHint("Enter notes for your scratchpad.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, isSaving ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm)
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

    @ViewBuilder
    private var standardScratchpadBody: some View {
        Group {
            if isEditing {
                TextEditor(text: $draft)
                    .appFont(.body)
                    .focused($isEditorFocused)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Scratchpad text")
                    .accessibilityHint("Enter notes for your scratchpad.")
            } else if draft.isEmpty {
                scratchpadEmptyState {
                    beginEditing()
                }
            } else {
                ScrollView {
                    Text(draft)
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

    private var usesPhoneSheetLayout: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
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
        if usesPhoneSheetLayout, !hasLoaded {
            isEditing = !stripped.isEmpty
            isEditorFocused = !stripped.isEmpty
        }
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

    @MainActor
    private func beginEditing() {
        isEditing = true
        isEditorFocused = true
    }

    @ViewBuilder
    private func scratchpadEmptyState(onTap: @escaping () -> Void) -> some View {
        EmptyStateView(
            title: "Scratchpad is empty.",
            subtitle: ScratchpadConstants.placeholder,
            icon: AppIcon.Action.compose
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct ScratchpadPopoverSurface: View {
    let api: any ScratchpadProviding
    let cache: CacheClient
    let scratchpadStore: ScratchpadStore

    var body: some View {
#if os(macOS)
        MacPopoverShell(type: scratchpadPopoverPanelType()) {
            scratchpadView
        }
#else
        // iPad popovers already provide the outer bubble chrome, so this path
        // only restores the internal spacing and width that the raw content lost.
        scratchpadView
            .padding(Self.iPadPopoverPadding)
            .frame(
                minWidth: Self.iPadPopoverWidth,
                idealWidth: Self.iPadPopoverWidth,
                maxWidth: Self.iPadPopoverWidth,
                alignment: .topLeading
            )
#endif
    }

    private var scratchpadView: some View {
        ScratchpadPopoverView(
            api: api,
            cache: cache,
            scratchpadStore: scratchpadStore
        )
    }

    private static var iPadPopoverPadding: CGFloat {
        DesignTokens.Spacing.md
    }

    private static var iPadPopoverWidth: CGFloat {
        MacPopoverShell<EmptyView>.minimumWidth(for: scratchpadPopoverPanelType())
    }
}

private struct ScratchpadHeaderRow: View {
    let isSaving: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ScratchpadConstants.title)
                    .appFont(.subheading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                if isSaving {
                    statusText("Saving...", color: .secondary)
                }
            }
            if !isSaving, let errorMessage {
                ScratchpadErrorBannerView(errorMessage: errorMessage)
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

private struct ScratchpadErrorBannerView: View {
    let errorMessage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(appIcon: AppIcon.State.warningFilled)
                .appFont(.caption)
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

private struct ScratchpadContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

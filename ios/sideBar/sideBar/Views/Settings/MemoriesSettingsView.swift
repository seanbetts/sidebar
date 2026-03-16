import SwiftUI
import sideBarShared
import MarkdownUI

// MARK: - MemoriesSettingsDetailView

struct MemoriesSettingsDetailView: View {
    @ObservedObject var viewModel: MemoriesViewModel
    @State private var searchQuery: String = ""
    @State private var selection: String?
    @State private var hasLoaded = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        #if os(macOS)
        macInspectorBody
        #else
        NavigationSplitView {
            VStack(spacing: 0) {
                header
                listContent
            }
            .background(DesignTokens.Colors.settingsBackground)
        } detail: {
            detailContent
                .background(DesignTokens.Colors.settingsBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load() }
            }
            if selection == nil {
                selection = viewModel.selectedMemoryId
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            Task { await viewModel.selectMemory(id: newValue) }
        }
        .onChange(of: viewModel.selectedMemoryId) { _, newValue in
            selection = newValue
        }
        #endif
    }

    #if os(macOS)
    private var macInspectorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                SettingsMacPanelCard {
                    SettingsMacSectionIntro(
                        title: "Memories",
                        message: "Browse the saved memories your assistant can reference during future work."
                    )

                    if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                        SettingsMacStatusBanner(message: error, tone: .error)
                    }

                    memoryListContent
                }

                SettingsMacPanelCard {
                    detailInspectorContent
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.Colors.settingsBackground)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load() }
            }
            if selection == nil {
                selection = viewModel.selectedMemoryId
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            Task { await viewModel.selectMemory(id: newValue) }
        }
        .onChange(of: viewModel.selectedMemoryId) { _, newValue in
            selection = newValue
        }
    }

    @ViewBuilder
    private var memoryListContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            memorySearchField

            if viewModel.isLoading && viewModel.items.isEmpty {
                LoadingView(message: "Loading memories…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if filteredItems.isEmpty {
                SettingsMacStatusBanner(
                    message: searchQuery.trimmed.isEmpty
                        ? "No memories saved yet."
                        : "No memories match that search.",
                    tone: .info
                )
            } else {
                LazyVStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(filteredItems) { item in
                        SettingsMacSkillRow(
                            title: displayName(item.path),
                            subtitle: item.content,
                            systemImage: selection == item.id ? "bookmark.fill" : "bookmark"
                        ) {
                            EmptyView()
                        }
                        .onTapGesture {
                            selection = item.id
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                                .stroke(
                                    selection == item.id
                                        ? DesignTokens.Colors.textPrimary.opacity(0.18)
                                        : .clear,
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var memorySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            TextField("Search memories", text: $searchQuery)
                .textFieldStyle(.plain)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Colors.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var detailInspectorContent: some View {
        if let memory = viewModel.active {
            SettingsMacSectionIntro(
                title: displayName(memory.path),
                message: "Review the memory content currently available to the assistant."
            )

            SideBarMarkdown(text: memory.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if viewModel.isLoadingDetail {
            LoadingView(message: "Loading memory…")
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if let error = viewModel.errorMessage, viewModel.selectedMemoryId != nil {
            SettingsMacStatusBanner(message: error, tone: .error)
        } else {
            SettingsMacStatusBanner(
                message: "Select a memory from the list to review its contents here.",
                tone: .info
            )
        }
    }
    #endif

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                TextField("Search memories", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .appFont(.subheadline)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.Colors.settingsFormBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
        }
        .padding(DesignTokens.Spacing.md)
    }

    @ViewBuilder
    private var listContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            SidebarListSkeleton(rowCount: 8, showSubtitle: false)
        } else if let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(
                title: "Unable to load memories",
                subtitle: error,
                actionTitle: "Retry",
                style: .error
            ) {
                Task { await viewModel.load() }
            }
        } else if filteredItems.isEmpty {
            SidebarPanelPlaceholder(
                title: searchQuery.trimmed.isEmpty
                    ? "No memories yet."
                    : "No memories match that search."
            )
        } else {
            List(selection: $selection) {
                ForEach(filteredItems) { item in
                    MemoryRow(item: item, isSelected: selection == item.id)
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = item.id }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.Colors.settingsBackground)
            .refreshable {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let memory = viewModel.active {
            if horizontalSizeClass == .compact {
                ScrollView {
                    SideBarMarkdown(text: memory.content)
                        .padding(DesignTokens.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(displayName(memory.path))
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            } else {
                VStack(spacing: 0) {
                    detailHeader(memory: memory)
                    Divider()
                    ScrollView {
                        SideBarMarkdown(text: memory.content)
                            .padding(DesignTokens.Spacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if viewModel.isLoadingDetail {
            LoadingView(message: "Loading memory…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.selectedMemoryId != nil {
            PlaceholderView(
                title: "Unable to load memory",
                subtitle: error,
                actionTitle: "Retry"
            ) {
                guard let selectedId = viewModel.selectedMemoryId else { return }
                Task { await viewModel.selectMemory(id: selectedId) }
            }
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            LoadingView(message: "Loading memories…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.selectedMemoryId != nil {
            PlaceholderView(title: "Memory not available")
        } else {
            PlaceholderView(
                title: "Select a memory",
                subtitle: "Choose a memory from the sidebar to open it.",
                iconName: "bookmark"
            )
        }
    }

    private func detailHeader(memory: MemoryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark")
                .appFont(.titleLg)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(memory.path))
                    .appFont(.headline)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
    }

    private var filteredItems: [MemoryItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return viewModel.items }
        return viewModel.items.filter { item in
            item.path.lowercased().contains(needle) ||
            item.content.lowercased().contains(needle)
        }
    }

    private func displayName(_ path: String) -> String {
        var trimmed = path
        if trimmed.hasPrefix("/memories/") {
            trimmed = String(trimmed.dropFirst("/memories/".count))
        }
        if trimmed.hasSuffix(".md") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.isEmpty ? "untitled" : trimmed
    }

    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct MemoryRow: View {
    let item: MemoryItem
    let isSelected: Bool

    var body: some View {
        SelectableRow(isSelected: isSelected) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(item.path))
                    .appFont(.subheadlineSemibold)
                    .lineLimit(2)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
        }
    }

    private func displayName(_ path: String) -> String {
        var trimmed = path
        if trimmed.hasPrefix("/memories/") {
            trimmed = String(trimmed.dropFirst("/memories/".count))
        }
        if trimmed.hasSuffix(".md") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.isEmpty ? "untitled" : trimmed
    }
}

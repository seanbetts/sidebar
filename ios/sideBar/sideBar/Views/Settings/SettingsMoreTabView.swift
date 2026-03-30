import MarkdownUI
import sideBarShared
import SwiftUI

struct SettingsMoreTabView: View {
    @ObservedObject var memoriesViewModel: MemoriesViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.Colors.settingsBackground
                    .ignoresSafeArea()

                List {
                    NavigationLink(value: Destination.memories) {
                        destinationRow(for: .memories)
                    }

                    NavigationLink(value: Destination.app) {
                        destinationRow(for: .app)
                    }
                }
                .settingsMoreListStyle()
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Colors.settingsBackground)
            }
            .navigationTitle("More")
            .settingsMoreInlineNavigationTitleDisplayMode()
            .navigationDestination(for: Destination.self) { destination in
                destinationView(for: destination)
                    .background(DesignTokens.Colors.settingsBackground)
                    .navigationTitle(destination.title)
                    .settingsMoreInlineNavigationTitleDisplayMode()
            }
        }
    }

    private func destinationRow(for destination: Destination) -> some View {
        Label(destination.title, systemImage: destination.systemImage)
            .appFont(.subheadline)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .padding(.vertical, DesignTokens.Spacing.xxsPlus)
    }

    @ViewBuilder
    private func destinationView(for destination: Destination) -> some View {
        switch destination {
        case .memories:
            SettingsMoreMemoriesBrowser(viewModel: memoriesViewModel)
        case .app:
            GeneralSettingsView()
        }
    }
}

extension SettingsMoreTabView {
    enum Destination: String, CaseIterable, Identifiable, Hashable {
        case memories
        case app

        var id: String { rawValue }

        var title: String {
            switch self {
            case .memories:
                return "Memories"
            case .app:
                return "App"
            }
        }

        var systemImage: String {
            switch self {
            case .memories:
                return "bookmark"
            case .app:
                return "gearshape"
            }
        }
    }
}

private struct SettingsMoreMemoriesBrowser: View {
    @ObservedObject var viewModel: MemoriesViewModel
    @State private var searchQuery = ""
    @State private var hasLoaded = false

    var body: some View {
        ZStack {
            DesignTokens.Colors.settingsBackground
                .ignoresSafeArea()

            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    LoadingView(message: "Loading memories…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                    SidebarPanelPlaceholder(
                        title: "Unable to load memories",
                        subtitle: error,
                        actionTitle: "Retry",
                        style: .error
                    ) {
                        Task { await viewModel.load() }
                    }
                } else if filteredItems.isEmpty {
                    if searchQuery.trimmed.isEmpty {
                        EmptyStateView(
                            title: "No memories yet",
                            subtitle: "Memories saved from your chats appear here.",
                            systemImage: "bookmark"
                        )
                    } else {
                        EmptyStateView(
                            title: "No memories match that search",
                            systemImage: "magnifyingglass"
                        )
                    }
                } else {
                    List {
                        Section {
                            ForEach(filteredItems) { item in
                                NavigationLink(value: item.id) {
                                    SettingsMoreMemoryRow(item: item)
                                }
                            }
                        }
                    }
                    .settingsMoreListStyle()
                    .scrollContentBackground(.hidden)
                    .background(DesignTokens.Colors.settingsBackground)
                    .refreshable {
                        await viewModel.load()
                    }
                }
            }
        }
        .searchable(text: $searchQuery, prompt: "Search memories")
        .navigationDestination(for: String.self) { memoryId in
            SettingsMoreMemoryDetailView(viewModel: viewModel, memoryId: memoryId)
                .settingsMoreInlineNavigationTitleDisplayMode()
        }
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load() }
            }
        }
    }

    private var filteredItems: [MemoryItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return viewModel.items }
        return viewModel.items.filter { item in
            item.path.lowercased().contains(needle) ||
            item.content.lowercased().contains(needle)
        }
    }
}

private struct SettingsMoreMemoryDetailView: View {
    @ObservedObject var viewModel: MemoriesViewModel
    let memoryId: String

    var body: some View {
        ZStack {
            DesignTokens.Colors.settingsBackground
                .ignoresSafeArea()

            Group {
                if viewModel.isLoadingDetail && displayedMemory == nil {
                    LoadingView(message: "Loading memory…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, displayedMemory == nil {
                    PlaceholderView(
                        title: "Unable to load memory",
                        subtitle: error,
                        actionTitle: "Retry"
                    ) {
                        Task { await viewModel.selectMemory(id: memoryId) }
                    }
                } else if let memory = displayedMemory {
                    ScrollView {
                        SideBarMarkdown(text: memory.content)
                            .padding(DesignTokens.Spacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    PlaceholderView(title: "Memory not available")
                }
            }
        }
        .navigationTitle(displayName(displayedMemory?.path ?? ""))
        .task(id: memoryId) {
            if viewModel.selectedMemoryId != memoryId || viewModel.active?.id != memoryId {
                await viewModel.selectMemory(id: memoryId)
            }
        }
    }

    private var displayedMemory: MemoryItem? {
        if viewModel.active?.id == memoryId {
            return viewModel.active
        }
        return viewModel.items.first { $0.id == memoryId }
    }

    private func displayName(_ path: String) -> String {
        var trimmed = path
        if trimmed.hasPrefix("/memories/") {
            trimmed = String(trimmed.dropFirst("/memories/".count))
        }
        if trimmed.hasSuffix(".md") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.isEmpty ? "Memory" : trimmed
    }
}

private struct SettingsMoreMemoryRow: View {
    let item: MemoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(displayName(item.path), systemImage: "bookmark")
                .appFont(.subheadlineSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text(item.content)
                .appFont(.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(2)
        }
        .padding(.vertical, DesignTokens.Spacing.xxsPlus)
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

private extension View {
    @ViewBuilder
    func settingsMoreListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.sidebar)
        #else
        self.listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    func settingsMoreInlineNavigationTitleDisplayMode() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

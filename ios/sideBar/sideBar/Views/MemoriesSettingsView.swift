import SwiftUI
import MarkdownUI

// MARK: - MemoriesSettingsView

struct MemoriesSettingsDetailView: View {
    @ObservedObject var viewModel: MemoriesViewModel
    @State private var searchQuery: String = ""
    @State private var selection: String? = nil
    @State private var hasLoaded = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                header
                listContent
            }
            .background(listBackground)
        } detail: {
            detailContent
                .background(DesignTokens.Colors.background)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search memories", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .font(.subheadline)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(searchFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(searchBorder, lineWidth: 1)
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
                actionTitle: "Retry"
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
            .background(listBackground)
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
                .font(DesignTokens.Typography.titleLg)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(memory.path))
                    .font(.headline)
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

    private func formattedDate(_ value: String) -> String? {
        guard let date = DateParsing.parseISO8601(value) else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    private var searchFill: Color {
        if colorScheme == .dark {
            return DesignTokens.Colors.surface
        }
        return DesignTokens.Colors.input
    }

    private var listBackground: Color {
        if colorScheme == .dark {
            return DesignTokens.Colors.background
        }
        return DesignTokens.Colors.sidebar
    }

    private var searchBorder: Color {
        DesignTokens.Colors.border
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SelectableRow(isSelected: isSelected, rowBackground: rowBackground) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(item.path))
                    .font(DesignTokens.Typography.subheadlineSemibold)
                    .lineLimit(1)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
        }
    }

    private var rowBackground: Color {
        colorScheme == .dark ? DesignTokens.Colors.surface : DesignTokens.Colors.background
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

    private func formattedDate(_ value: String) -> String? {
        guard let date = DateParsing.parseISO8601(value) else { return nil }
        return MemoriesSettingsDetailView.dateFormatter.string(from: date)
    }

}

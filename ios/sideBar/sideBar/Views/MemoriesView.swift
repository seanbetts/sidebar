import SwiftUI
import MarkdownUI

struct MemoriesDetailView: View {
    @ObservedObject var viewModel: MemoriesViewModel
    @State private var searchQuery: String = ""
    @State private var selection: String? = nil
    @State private var hasLoaded = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                listContent
            }
        } detail: {
            detailContent
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
            Text("Memories")
                .font(.subheadline.weight(.semibold))

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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
        .padding(16)
    }

    @ViewBuilder
    private var listContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(title: error)
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
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let memory = viewModel.active {
            VStack(spacing: 0) {
                detailHeader(memory: memory)
                Divider()
                ScrollView {
                    Markdown(memory.content)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if viewModel.isLoadingDetail {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.selectedMemoryId != nil {
            PlaceholderView(title: "Memory not available")
        } else {
            PlaceholderView(title: "Select a memory")
        }
    }

    private func detailHeader(memory: MemoryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(memory.path))
                    .font(.headline)
                if let updated = formattedDate(memory.updatedAt) {
                    Text(updated)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
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
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var searchBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
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
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName(item.path))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let updated = formattedDate(item.updatedAt) {
                Text(updated)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(isSelected ? selectionBackground : rowBackground)
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
        return MemoriesDetailView.dateFormatter.string(from: date)
    }

    private var selectionBackground: Color {
        #if os(macOS)
        return Color(nsColor: .selectedContentBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var rowBackground: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

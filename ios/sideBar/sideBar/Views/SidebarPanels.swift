import SwiftUI

public struct ConversationsPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        ConversationsPanelView(viewModel: environment.chatViewModel)
            .task {
                await environment.chatViewModel.loadConversations()
            }
    }
}

private struct ConversationsPanelView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingConversations && viewModel.conversations.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading conversations…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.conversations.isEmpty {
                SidebarPanelPlaceholder(title: "No conversations")
            } else {
                List {
                    ForEach(viewModel.groupedConversations) { group in
                        Section(group.title) {
                            ForEach(group.conversations) { conversation in
                                Button {
                                    Task { await viewModel.selectConversation(id: conversation.id) }
                                } label: {
                                    ConversationRow(
                                        conversation: conversation,
                                        isSelected: viewModel.selectedConversationId == conversation.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(rowBackground(isSelected: viewModel.selectedConversationId == conversation.id))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .refreshable {
                    await viewModel.refreshConversations()
                }
            }
        }
    }

    private func rowBackground(isSelected: Bool) -> Color {
        guard isSelected else {
            return Color.clear
        }
        #if os(macOS)
        return Color(nsColor: .selectedContentBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conversation.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .primary : .primary)
                .lineLimit(1)
            if let preview = conversation.firstMessage, !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(formattedDate)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var formattedDate: String {
        guard let date = DateParsing.parseISO8601(conversation.updatedAt) else {
            return conversation.updatedAt
        }
        return DateFormatter.chatList.string(from: date)
    }
}

private extension DateFormatter {
    static let chatList: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

public struct NotesPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        NotesPanelView(viewModel: environment.notesViewModel)
    }
}

private struct NotesPanelView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var hasLoaded = false
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if showInlineSearch {
                searchBar
            }
            Group {
                if viewModel.tree == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResultsView
                } else {
                    notesTreeView
                }
            }
        }
        #if !os(macOS)
        .searchable(
            text: $viewModel.searchQuery,
            placement: .navigationBarDrawer(displayMode: .always)
        )
        #endif
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.loadTree() }
            }
        }
        .onChange(of: viewModel.searchQuery) { _, newValue in
            viewModel.updateSearch(query: newValue)
        }
    }

    private var searchResultsView: some View {
        List {
            if viewModel.isSearching {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching…")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.searchResults.isEmpty {
                Text("No matching notes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.searchResults, id: \.path) { node in
                    NotesTreeRow(
                        item: FileNodeItem(
                            id: node.path,
                            name: node.name,
                            type: node.type,
                            children: nil
                        ),
                        isSelected: viewModel.selectedNoteId == node.path
                    ) {
                        Task { await viewModel.selectNote(id: node.path) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func buildItems(from nodes: [FileNode]) -> [FileNodeItem] {
        nodes.map { node in
            let children = node.type == .directory ? buildItems(from: node.children ?? []) : nil
            return FileNodeItem(
                id: node.path,
                name: node.name,
                type: node.type,
                children: children
            )
        }
    }

    private var notesTreeView: some View {
        List {
            OutlineGroup(buildItems(from: viewModel.tree?.children ?? []), children: \.children) { item in
                NotesTreeRow(
                    item: item,
                    isSelected: viewModel.selectedNoteId == item.id
                ) {
                    if item.isFile {
                        Task { await viewModel.selectNote(id: item.id) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            await viewModel.loadTree()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search notes", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
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

    private var showInlineSearch: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass != .compact
        #endif
    }
}

private struct NotesTreeRow: View {
    let item: FileNodeItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: item.isFile ? "doc.text" : "folder")
                    .foregroundStyle(item.isFile ? .secondary : .primary)
                Text(item.displayName)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? selectionBackground : rowBackground)
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

private struct FileNodeItem: Identifiable {
    let id: String
    let name: String
    let type: FileNodeType
    let children: [FileNodeItem]?

    var isFile: Bool { type == .file }

    var displayName: String {
        if isFile, name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }
}

public struct FilesPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        FilesPanelView(viewModel: environment.ingestionViewModel)
    }
}

private struct FilesPanelView: View {
    @ObservedObject var viewModel: IngestionViewModel
    @State private var hasLoaded = false
    @State private var selection: String? = nil
    @State private var expandedCategories: Set<String> = []

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage {
                SidebarPanelPlaceholder(title: message)
            } else if readyItems.isEmpty && processingItems.isEmpty && failedItems.isEmpty {
                SidebarPanelPlaceholder(title: "No files yet.")
            } else {
                filesListView
            }
        }
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load() }
            }
            if selection == nil {
                selection = viewModel.selectedFileId
            }
            initializeExpandedCategoriesIfNeeded()
        }
        .onChange(of: categoriesWithItems) { _, _ in
            initializeExpandedCategoriesIfNeeded()
        }
        .onChange(of: selection) { _, newValue in
            guard let fileId = newValue else { return }
            open(fileId: fileId)
        }
    }

    private var filesListView: some View {
        List(selection: $selection) {
            if !pinnedItems.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedItems, id: \.file.id) { item in
                        FilesIngestionRow(item: item, isSelected: viewModel.selectedFileId == item.file.id)
                            .tag(item.file.id)
                            .contentShape(Rectangle())
                            .onTapGesture { open(item: item) }
                    }
                }
            }

            if !categorizedItems.isEmpty {
                ForEach(categoryOrder, id: \.self) { category in
                    if let items = categorizedItems[category], !items.isEmpty {
                        Section {
                            CategoryToggleRow(
                                title: categoryLabels[category] ?? "Files",
                                isExpanded: expandedCategories.contains(category)
                            ) {
                                toggleCategory(category)
                            }
                            if expandedCategories.contains(category) {
                                ForEach(items, id: \.file.id) { item in
                                    FilesIngestionRow(item: item, isSelected: viewModel.selectedFileId == item.file.id)
                                        .tag(item.file.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { open(item: item) }
                                }
                            }
                        }
                    }
                }
            }

            if !processingItems.isEmpty || !failedItems.isEmpty {
                Section("Uploads") {
                    ForEach(processingItems, id: \.file.id) { item in
                        FilesIngestionRow(item: item, isSelected: viewModel.selectedFileId == item.file.id)
                            .tag(item.file.id)
                            .contentShape(Rectangle())
                            .onTapGesture { open(item: item) }
                    }
                    ForEach(failedItems, id: \.file.id) { item in
                        FilesIngestionRow(item: item, isSelected: viewModel.selectedFileId == item.file.id)
                            .tag(item.file.id)
                            .contentShape(Rectangle())
                            .onTapGesture { open(item: item) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            await viewModel.load()
        }
    }

    private func open(item: IngestionListItem) {
        selection = item.file.id
        open(fileId: item.file.id)
    }

    private func open(fileId: String) {
        Task { await viewModel.selectFile(fileId: fileId) }
    }

    private func toggleCategory(_ category: String) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }

    private func initializeExpandedCategoriesIfNeeded() {
        if expandedCategories.isEmpty {
            expandedCategories = []
        }
    }

    private var processingItems: [IngestionListItem] {
        viewModel.items.filter { item in
            let status = item.job.status ?? ""
            return !["ready", "failed", "canceled"].contains(status)
        }
    }

    private var failedItems: [IngestionListItem] {
        viewModel.items.filter { ($0.job.status ?? "") == "failed" }
    }

    private var readyItems: [IngestionListItem] {
        viewModel.items.filter { item in
            (item.job.status ?? "") == "ready" && item.recommendedViewer != nil
        }
    }

    private var pinnedItems: [IngestionListItem] {
        readyItems
            .filter { $0.file.pinned ?? false }
            .sorted { lhs, rhs in
                let left = lhs.file.pinnedOrder ?? Int.max
                let right = rhs.file.pinnedOrder ?? Int.max
                if left != right {
                    return left < right
                }
                let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
                let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
                return leftDate > rightDate
            }
    }

    private var categorizedItems: [String: [IngestionListItem]] {
        let unpinned = readyItems.filter { !($0.file.pinned ?? false) }
        let grouped = unpinned.reduce(into: [String: [IngestionListItem]]()) { result, item in
            let category = item.file.category ?? "other"
            result[category, default: []].append(item)
        }
        return grouped.mapValues { items in
            items.sorted { lhs, rhs in
                let left = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
                let right = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
                return left > right
            }
        }
    }

    private var categoriesWithItems: [String] {
        categoryOrder.filter { categorizedItems[$0]?.isEmpty == false }
    }

    private var categoryLabels: [String: String] {
        [
            "documents": "Documents",
            "images": "Images",
            "audio": "Audio",
            "video": "Video",
            "spreadsheets": "Spreadsheets",
            "reports": "Reports",
            "presentations": "Presentations",
            "other": "Other"
        ]
    }

    private var categoryOrder: [String] {
        ["documents", "images", "audio", "video", "spreadsheets", "reports", "presentations", "other"]
    }
}

private struct FilesIngestionRow: View {
    let item: IngestionListItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(stripFileExtension(item.file.filenameOriginal))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.file.pinned == true {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(isSelected ? selectionBackground : rowBackground)
    }

    private var statusText: String {
        if let message = item.job.userMessage, !message.isEmpty {
            return message
        }
        if let status = item.job.status {
            return status.capitalized
        }
        return "Processing"
    }

    private var iconName: String {
        switch item.recommendedViewer {
        case "viewer_pdf":
            return "doc.richtext"
        case "viewer_json":
            return "tablecells"
        case "viewer_video":
            return "video"
        case "image_original":
            return "photo"
        case "audio_original":
            return "waveform"
        case "text_original", "ai_md":
            return "doc.text"
        default:
            return "doc"
        }
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

private struct CategoryToggleRow: View {
    let title: String
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

public struct WebsitesPanel: View {
    public init() {
    }

    public var body: some View {
        SidebarPanelPlaceholder(title: "Websites")
    }
}

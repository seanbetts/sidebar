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

    var body: some View {
        VStack(spacing: 0) {
            header
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Notes")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(searchFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(searchBorder, lineWidth: 1)
                )
                .accessibilityLabel("Add note")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
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
    @State private var searchQuery: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage {
                SidebarPanelPlaceholder(title: message)
            } else if filteredReadyItems.isEmpty && filteredProcessingItems.isEmpty && filteredFailedItems.isEmpty {
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Files")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(searchFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(searchBorder, lineWidth: 1)
                )
                .accessibilityLabel("Add file")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search files", text: $searchQuery)
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

            if !filteredProcessingItems.isEmpty || !filteredFailedItems.isEmpty {
                Section("Uploads") {
                    ForEach(filteredProcessingItems, id: \.file.id) { item in
                        FilesIngestionRow(item: item, isSelected: viewModel.selectedFileId == item.file.id)
                            .tag(item.file.id)
                            .contentShape(Rectangle())
                            .onTapGesture { open(item: item) }
                    }
                    ForEach(filteredFailedItems, id: \.file.id) { item in
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

    private var filteredReadyItems: [IngestionListItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return readyItems }
        return readyItems.filter { item in
            item.file.filenameOriginal.lowercased().contains(needle)
        }
    }

    private var filteredProcessingItems: [IngestionListItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return processingItems }
        return processingItems.filter { item in
            item.file.filenameOriginal.lowercased().contains(needle)
        }
    }

    private var filteredFailedItems: [IngestionListItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return failedItems }
        return failedItems.filter { item in
            item.file.filenameOriginal.lowercased().contains(needle)
        }
    }

    private var pinnedItems: [IngestionListItem] {
        filteredReadyItems
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
        let unpinned = filteredReadyItems.filter { !($0.file.pinned ?? false) }
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
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        WebsitesPanelView(viewModel: environment.websitesViewModel)
    }
}

private struct WebsitesPanelView: View {
    @ObservedObject var viewModel: WebsitesViewModel
    @State private var searchQuery: String = ""
    @State private var hasLoaded = false
    @State private var isArchiveExpanded = false
    @State private var selection: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load() }
            }
            if selection == nil {
                selection = viewModel.active?.id
            }
        }
        .onChange(of: viewModel.active?.id) { _, newValue in
            selection = newValue
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Websites")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(actionBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(actionBorder, lineWidth: 1)
                )
                .accessibilityLabel("Add website")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search websites...", text: $searchQuery)
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
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(title: error)
        } else if searchQuery.trimmed.isEmpty && viewModel.items.isEmpty {
            SidebarPanelPlaceholder(title: "No websites yet.")
        } else if !searchQuery.trimmed.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Results")
                    if filteredItems.isEmpty {
                        SidebarPanelPlaceholder(title: "No results.")
                    } else {
                        ForEach(filteredItems, id: \.id) { item in
                            WebsiteRow(
                                item: item,
                                isSelected: selection == item.id
                            ) {
                                open(item: item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } else {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        websitesSection
                        Spacer(minLength: 12)
                        archiveSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(minHeight: proxy.size.height)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var websitesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Pinned")
            if pinnedItemsSorted.isEmpty {
                Text("No pinned websites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pinnedItemsSorted, id: \.id) { item in
                        WebsiteRow(
                            item: item,
                            isSelected: selection == item.id
                        ) {
                            open(item: item)
                        }
                    }
                }
            }

            sectionTitle("Websites")
            if mainItems.isEmpty {
                Text("No websites saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(mainItems, id: \.id) { item in
                        WebsiteRow(
                            item: item,
                            isSelected: selection == item.id
                        ) {
                            open(item: item)
                        }
                    }
                }
            }
        }
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Archive")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isArchiveExpanded.toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isArchiveExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)

            if isArchiveExpanded {
                if archivedItems.isEmpty {
                    Text("No archived websites")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(archivedItems, id: \.id) { item in
                            WebsiteRow(
                                item: item,
                                isSelected: selection == item.id
                            ) {
                                open(item: item)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func open(item: WebsiteItem) {
        selection = item.id
        Task { await viewModel.selectWebsite(id: item.id) }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private var pinnedItemsSorted: [WebsiteItem] {
        pinnedItems.sorted { lhs, rhs in
            let leftOrder = lhs.pinnedOrder ?? Int.max
            let rightOrder = rhs.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            let leftDate = DateParsing.parseISO8601(lhs.updatedAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.updatedAt) ?? .distantPast
            return leftDate > rightDate
        }
    }

    private var pinnedItems: [WebsiteItem] {
        viewModel.items.filter { $0.pinned && !$0.archived }
    }

    private var mainItems: [WebsiteItem] {
        viewModel.items.filter { !$0.pinned && !$0.archived }
    }

    private var archivedItems: [WebsiteItem] {
        viewModel.items.filter { $0.archived }
    }

    private var filteredItems: [WebsiteItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return viewModel.items }
        return viewModel.items.filter { item in
            item.title.lowercased().contains(needle) ||
            item.domain.lowercased().contains(needle) ||
            item.url.lowercased().contains(needle)
        }
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

    private var actionBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var actionBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
    }
}

private struct WebsiteRow: View {
    let item: WebsiteItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? item.url : item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(formatDomain(item.domain))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? selectionBackground : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func formatDomain(_ domain: String) -> String {
        domain.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    private var selectionBackground: Color {
        #if os(macOS)
        return Color(nsColor: .selectedContentBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

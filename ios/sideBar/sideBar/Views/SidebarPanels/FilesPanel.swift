import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - FilesPanel

public struct FilesPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        FilesPanelView(viewModel: environment.ingestionViewModel)
    }
}

private struct FilesPanelView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var viewModel: IngestionViewModel
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasLoaded = false
    @State private var expandedCategories: Set<String> = []
    @State private var searchQuery: String = ""
    @State private var listAppeared = false
    @State private var isDeleteAlertPresented = false
    @State private var deleteTarget: IngestionListItem? = nil
    @State private var pinTarget: IngestionListItem? = nil
    @State private var isFileImporterPresented = false
    @State private var isYouTubeAlertPresented = false
    @State private var newYouTubeUrl: String = ""
    @State private var knownFileIds: Set<String> = []
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        content
    }
}

extension FilesPanelView {
    private var content: some View {
        mainContent
            .frame(maxHeight: .infinity)
            .alert(deleteDialogTitle, isPresented: $isDeleteAlertPresented) {
                Button("Delete", role: .destructive) {
                    confirmDelete()
                }
                Button("Cancel", role: .cancel) {
                    clearDeleteTarget()
                }
            } message: {
                Text("This will remove the file and cannot be undone.")
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
            .alert("Add YouTube video", isPresented: $isYouTubeAlertPresented) {
                TextField("youtube.com", text: $newYouTubeUrl)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .submitLabel(.done)
                    #endif
                    .onSubmit {
                        addYouTube()
                    }
                Button(viewModel.isIngestingYouTube ? "Adding..." : "Add") {
                    addYouTube()
                }
                .disabled(viewModel.isIngestingYouTube || newYouTubeUrl.trimmed.isEmpty)
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    newYouTubeUrl = ""
                }
            }
            .onAppear {
                if !hasLoaded {
                    hasLoaded = true
                    Task { await viewModel.load() }
                }
                initializeExpandedCategoriesIfNeeded()
                knownFileIds = Set(viewModel.items.map { $0.file.id })
            }
            .onChange(of: categoriesWithItems) { _, _ in
                initializeExpandedCategoriesIfNeeded()
            }
            .onChange(of: viewModel.items.map { $0.file.id }) { _, newIds in
                let newIdSet = Set(newIds)
                let addedIds = newIdSet.subtracting(knownFileIds)
                if !addedIds.isEmpty {
                    for item in viewModel.items where addedIds.contains(item.file.id) {
                        if item.file.mimeOriginal.lowercased().contains("youtube") {
                            expandedCategories.insert("video")
                            break
                        }
                    }
                }
                knownFileIds = newIdSet
            }
            .onReceive(environment.$shortcutActionEvent) { event in
                guard let event, event.section == .files else { return }
                switch event.action {
                case .focusSearch:
                    isSearchFocused = true
                case .newItem:
                    isFileImporterPresented = true
                case .navigateList(let direction):
                    navigateFilesList(direction: direction)
                default:
                    break
                }
            }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            if viewModel.isLoading && viewModel.items.isEmpty {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if let message = viewModel.errorMessage {
                SidebarPanelPlaceholder(
                    title: "Unable to load files",
                    subtitle: message,
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.load() }
                }
            } else if filteredItems.isEmpty {
                if searchQuery.trimmed.isEmpty {
                    SidebarPanelPlaceholder(title: "No files yet.")
                } else {
                    SidebarPanelPlaceholder(title: "No results.")
                }
            } else {
                filesListView
            }
        }
    }

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Files") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Button {
                        newYouTubeUrl = ""
                        isYouTubeAlertPresented = true
                    } label: {
                        Image(systemName: "play.rectangle")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add YouTube video")
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add file")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $searchQuery, placeholder: "Search files", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var filesListView: some View {
        List {
            if !searchQuery.trimmed.isEmpty {
                ForEach(Array(searchResults.enumerated()), id: \.element.file.id) { index, item in
                    let row = FilesIngestionRow(
                        item: item,
                        isSelected: viewModel.selectedFileId == item.file.id,
                        onPinToggle: pinAction(for: item),
                        onDelete: deleteAction(for: item)
                    )
                    if isFolder(item) {
                        row
                            .staggeredAppear(index: index, isActive: listAppeared)
                    } else {
                        row
                            .staggeredAppear(index: index, isActive: listAppeared)
                            .onTapGesture { open(item: item) }
                    }
                }
            } else {
                if !pinnedItems.isEmpty {
                    Section("Pinned") {
                        ForEach(Array(pinnedItems.enumerated()), id: \.element.file.id) { index, item in
                            let row = FilesIngestionRow(
                                item: item,
                                isSelected: viewModel.selectedFileId == item.file.id,
                                onPinToggle: pinAction(for: item),
                                onDelete: deleteAction(for: item)
                            )
                            if isFolder(item) {
                                row
                                    .staggeredAppear(index: index, isActive: listAppeared)
                            } else {
                                row
                                    .staggeredAppear(index: index, isActive: listAppeared)
                                    .onTapGesture { open(item: item) }
                            }
                        }
                    }
                }

                if !categorizedItems.isEmpty {
                    Section("Files") {
                        ForEach(Array(categoryOrder.enumerated()), id: \.element) { categoryIndex, category in
                            if let items = categorizedItems[category], !items.isEmpty {
                                DisclosureGroup(
                                    isExpanded: bindingForCategory(category)
                                ) {
                                    ForEach(Array(items.enumerated()), id: \.element.file.id) { itemIndex, item in
                                        let row = FilesIngestionRow(
                                            item: item,
                                            isSelected: viewModel.selectedFileId == item.file.id,
                                            onPinToggle: pinAction(for: item),
                                            onDelete: deleteAction(for: item)
                                        )
                                        if isFolder(item) {
                                            row
                                                .staggeredAppear(
                                                    index: categoryIndex + itemIndex,
                                                    isActive: listAppeared
                                                )
                                        } else {
                                            row
                                                .staggeredAppear(
                                                    index: categoryIndex + itemIndex,
                                                    isActive: listAppeared
                                                )
                                                .onTapGesture { open(item: item) }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: categoryIconName(category))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20, alignment: .center)
                                        Text(categoryLabels[category] ?? "Files")
                                    }
                                    .font(.subheadline)
                                }
                                .listRowBackground(rowBackground)
                            }
                        }
                    }
                }
            }

        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
        .refreshable {
            await viewModel.load()
        }
        .onAppear {
            listAppeared = !viewModel.isLoading
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            listAppeared = !isLoading
        }
    }
}

extension FilesPanelView {
    private func open(item: IngestionListItem) {
        open(fileId: item.file.id)
    }

    private func open(fileId: String) {
        viewModel.prepareSelection(fileId: fileId)
        Task { await viewModel.selectFile(fileId: fileId) }
    }

    private func pinAction(for item: IngestionListItem) -> (() -> Void)? {
        guard item.file.category != "folder" else {
            return nil
        }
        return {
            pinTarget = item
            Task { await togglePin() }
        }
    }

    private func deleteAction(for item: IngestionListItem) -> (() -> Void)? {
        guard item.file.category != "folder" else {
            return nil
        }
        return {
            presentDelete(for: item)
        }
    }

    private func togglePin() async {
        guard let item = pinTarget else { return }
        let isPinned = item.file.pinned ?? false
        await viewModel.togglePinned(fileId: item.file.id, pinned: !isPinned)
        pinTarget = nil
    }

    private func presentDelete(for item: IngestionListItem) {
        deleteTarget = item
        isDeleteAlertPresented = true
    }

    private func confirmDelete() {
        guard let item = deleteTarget else { return }
        Task {
            let success = await viewModel.deleteFile(fileId: item.file.id)
            if !success {
                environment.toastCenter.show(message: "Failed to delete file")
            }
        }
        clearDeleteTarget()
    }

    private func clearDeleteTarget() {
        deleteTarget = nil
        isDeleteAlertPresented = false
    }

    private func navigateFilesList(direction: ShortcutListDirection) {
        let ids = filesNavigationItems()
        guard !ids.isEmpty else { return }
        let currentId = viewModel.selectedFileId
        let nextIndex: Int
        if let currentId, let index = ids.firstIndex(of: currentId) {
            nextIndex = direction == .next ? min(ids.count - 1, index + 1) : max(0, index - 1)
        } else {
            nextIndex = direction == .next ? 0 : ids.count - 1
        }
        open(fileId: ids[nextIndex])
    }

    private func filesNavigationItems() -> [String] {
        if !searchQuery.trimmed.isEmpty {
            return searchResults.filter { !isFolder($0) }.map { $0.file.id }
        }
        var ids: [String] = []
        ids.append(contentsOf: pinnedItems.filter { !isFolder($0) }.map { $0.file.id })
        for category in categoryOrder {
            if let items = categorizedItems[category] {
                ids.append(contentsOf: items.filter { !isFolder($0) }.map { $0.file.id })
            }
        }
        return ids
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            viewModel.addUploads(urls: urls)
        case .failure:
            environment.toastCenter.show(message: "Failed to add files")
        }
    }

    private func addYouTube() {
        let url = newYouTubeUrl.trimmed
        guard !url.isEmpty else { return }
        newYouTubeUrl = ""
        isYouTubeAlertPresented = false
        Task {
            if let message = await viewModel.ingestYouTube(url: url) {
                environment.toastCenter.show(message: message)
            }
        }
    }

    private var deleteDialogTitle: String {
        guard let deleteTarget else {
            return "Delete file"
        }
        let name = stripFileExtension(deleteTarget.file.filenameOriginal)
        return "Delete \"\(name)\"?"
    }

    private func isFolder(_ item: IngestionListItem) -> Bool {
        item.file.category == "folder"
    }

    private func bindingForCategory(_ category: String) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(category) },
            set: { isExpanded in
                if isExpanded {
                    expandedCategories.insert(category)
                } else {
                    expandedCategories.remove(category)
                }
            }
        )
    }

    private func initializeExpandedCategoriesIfNeeded() {
        if expandedCategories.isEmpty {
            expandedCategories = []
        }
    }

    private var filteredItems: [IngestionListItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return viewModel.items }
        return viewModel.items.filter { item in
            item.file.filenameOriginal.lowercased().contains(needle)
        }
    }

    private var searchResults: [IngestionListItem] {
        filteredItems.sorted { lhs, rhs in
            let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
            return leftDate > rightDate
        }
    }

    private var pinnedItems: [IngestionListItem] {
        filteredItems
            .filter { isReady($0) && ($0.file.pinned ?? false) }
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
        let unpinned = filteredItems.filter { !($0.file.pinned ?? false) }
        let grouped = unpinned.reduce(into: [String: [IngestionListItem]]()) { result, item in
            let category = categoryFor(item)
            result[category, default: []].append(item)
        }
        return grouped.mapValues { items in
            items.sorted { lhs, rhs in
                let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
                let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
                return leftDate > rightDate
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

    private func isReady(_ item: IngestionListItem) -> Bool {
        (item.job.status ?? "") == "ready" && item.recommendedViewer != nil
    }

    private func categoryFor(_ item: IngestionListItem) -> String {
        if let category = item.file.category, !category.isEmpty {
            return category
        }
        let normalized = item.file.mimeOriginal.split(separator: ";").first?
            .trimmed
            .lowercased() ?? item.file.mimeOriginal
        if normalized == "video/youtube" || normalized.hasPrefix("video/") {
            return "video"
        }
        if normalized.hasPrefix("image/") {
            return "images"
        }
        if normalized.hasPrefix("audio/") {
            return "audio"
        }
        if normalized == "application/pdf"
            || normalized == "text/plain"
            || normalized == "text/markdown"
            || normalized == "text/html"
            || normalized == "application/msword"
            || normalized == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" {
            return "documents"
        }
        if normalized == "application/vnd.ms-excel"
            || normalized == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            || normalized == "text/csv" {
            return "spreadsheets"
        }
        if normalized == "application/vnd.ms-powerpoint"
            || normalized == "application/vnd.openxmlformats-officedocument.presentationml.presentation" {
            return "presentations"
        }
        return "other"
    }

    private func categoryIconName(_ category: String) -> String {
        switch category {
        case "documents":
            return "doc.text"
        case "images":
            return "photo"
        case "audio":
            return "waveform"
        case "video":
            return "video"
        case "spreadsheets":
            return "tablecells"
        case "reports":
            return "chart.line.text.clipboard"
        case "presentations":
            return "rectangle.on.rectangle.angled"
        default:
            return "folder"
        }
    }

    private var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }

}

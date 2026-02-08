import Foundation
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers

extension FilesPanelView {
    func renameSheet() -> some View {
        RenameItemSheet(
            title: "Rename File",
            placeholder: "File name",
            text: $renameValue
        ) { newName in
            Task { await commitRename(to: newName) }
        }
    }

    func open(item: IngestionListItem) {
        open(fileId: item.file.id)
    }

    func open(fileId: String) {
        viewModel.prepareSelection(fileId: fileId)
        Task { await viewModel.selectFile(fileId: fileId) }
    }

    func pinAction(for item: IngestionListItem) -> (() -> Void)? {
        guard item.file.category != "folder" else {
            return nil
        }
        return {
            pinTarget = item
            Task { await togglePin() }
        }
    }

    func deleteAction(for item: IngestionListItem) -> (() -> Void)? {
        guard item.file.category != "folder" else {
            return nil
        }
        return {
            presentDelete(for: item)
        }
    }

    func togglePin() async {
        guard let item = pinTarget else { return }
        let isPinned = item.file.pinned ?? false
        await viewModel.togglePinned(fileId: item.file.id, pinned: !isPinned)
        pinTarget = nil
    }

    func presentDelete(for item: IngestionListItem) {
        deleteTarget = item
        isDeleteAlertPresented = true
    }

    func confirmDelete() {
        guard let item = deleteTarget else { return }
        Task {
            let success = await viewModel.deleteFile(fileId: item.file.id)
            if !success {
                appEnvironment.toastCenter.show(message: "Failed to delete file")
            }
        }
        clearDeleteTarget()
    }

    func clearDeleteTarget() {
        deleteTarget = nil
        isDeleteAlertPresented = false
    }

    func navigateFilesList(direction: ShortcutListDirection) {
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

    func filesNavigationItems() -> [String] {
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

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            viewModel.addUploads(urls: urls)
        case .failure:
            appEnvironment.toastCenter.show(message: "Failed to add files")
        }
    }

    func addYouTube() {
        let url = newYouTubeUrl.trimmed
        guard !url.isEmpty else { return }
        newYouTubeUrl = ""
        isYouTubeAlertPresented = false
        Task {
            if let message = await viewModel.ingestYouTube(url: url) {
                appEnvironment.toastCenter.show(message: message)
            }
        }
    }

    var deleteDialogTitle: String {
        guard let deleteTarget else {
            return "Delete file"
        }
        let name = stripFileExtension(deleteTarget.file.filenameOriginal)
        return "Delete \"\(name)\"?"
    }

    func isFolder(_ item: IngestionListItem) -> Bool {
        item.file.category == "folder"
    }

    func bindingForCategory(_ category: String) -> Binding<Bool> {
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

    func initializeExpandedCategoriesIfNeeded() {
        if expandedCategories.isEmpty {
            expandedCategories = []
        }
    }

    var filteredItems: [IngestionListItem] {
        let needle = searchQuery.trimmed.lowercased()
        let baseItems = viewModel.items.filter { $0.statusValue != "failed" }
        guard !needle.isEmpty else { return baseItems }
        return baseItems.filter { item in
            item.file.filenameOriginal.lowercased().contains(needle)
        }
    }

    var searchResults: [IngestionListItem] {
        filteredItems.sorted { lhs, rhs in
            let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
            return leftDate > rightDate
        }
    }

    var pinnedItems: [IngestionListItem] {
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

    var categorizedItems: [String: [IngestionListItem]] {
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

    var categoriesWithItems: [String] {
        categoryOrder.filter { categorizedItems[$0]?.isEmpty == false }
    }

    var categoryLabels: [String: String] {
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

    var categoryOrder: [String] {
        ["documents", "images", "audio", "video", "spreadsheets", "reports", "presentations", "other"]
    }

    func isReady(_ item: IngestionListItem) -> Bool {
        (item.job.status ?? "") == "ready" && item.recommendedViewer != nil
    }

    func categoryFor(_ item: IngestionListItem) -> String {
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

    func categoryIconName(_ category: String) -> String {
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

    var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

}

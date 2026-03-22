import Foundation
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers

extension FilesPanelView {
    var pinnedItems: [IngestionListItem] {
        let items = viewModel.panelPinnedItems
        guard !pinnedReorderDisplayedIDs.isEmpty else { return items }
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.file.id, $0) })
        return pinnedReorderDisplayedIDs.compactMap { lookup[$0] }
    }

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
        viewModel.panelNavigationFileIds
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

    func initializeKnownFileIdsBaselineIfNeeded() {
        guard FilesPanelExpansionPolicy.shouldInitializeBaseline(
            isLoading: viewModel.isLoading,
            awaitingInitialLoad: isAwaitingInitialLoad,
            hasBaseline: hasKnownFileIdsBaseline
        ) else {
            return
        }
        knownFileIds = FilesPanelExpansionPolicy.currentFileIds(from: viewModel.items)
        hasKnownFileIdsBaseline = true
    }

    var filteredItems: [IngestionListItem] {
        viewModel.panelFilteredItems
    }

    var searchResults: [IngestionListItem] {
        viewModel.panelSearchResults
    }

    var categorizedItems: [String: [IngestionListItem]] {
        viewModel.panelCategorizedItems
    }

    var categoriesWithItems: [String] {
        viewModel.panelCategoriesWithItems
    }

    var categoryLabels: [String: String] {
        IngestionViewModel.panelCategoryLabels
    }

    var categoryOrder: [String] {
        IngestionViewModel.panelCategoryOrder
    }

    func categoryIconName(_ category: String) -> String {
        viewModel.panelCategoryIconName(category)
    }

    func staggerIndex(for id: String, section: String? = nil) -> Int {
        let key = section.map { "\($0):\(id)" } ?? id
        return abs(key.hashValue % 32)
    }

    var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

}

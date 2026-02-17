import Foundation
import sideBarShared

// MARK: - IngestionViewModel+PanelData

extension IngestionViewModel {
    static let panelCategoryLabels: [String: String] = [
        "documents": "Documents",
        "images": "Images",
        "audio": "Audio",
        "video": "Video",
        "spreadsheets": "Spreadsheets",
        "reports": "Reports",
        "presentations": "Presentations",
        "other": "Other"
    ]

    static let panelCategoryOrder: [String] = [
        "documents", "images", "audio", "video", "spreadsheets", "reports", "presentations", "other"
    ]

    func panelCategoryIconName(_ category: String) -> String {
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

    func updatePanelDerivedState() {
        let needle = panelSearchQuery.trimmed.lowercased()
        let baseItems = items.filter { $0.statusValue != "failed" }
        let filtered = needle.isEmpty ? baseItems : baseItems.filter { item in
            item.file.filenameOriginal.lowercased().contains(needle)
        }
        let searchResults = filtered.sorted(by: Self.sortByCreatedDateDescending)
        let pinnedItems = filtered
            .filter { $0.file.pinned ?? false }
            .sorted(by: Self.sortPinnedItems)
        let unpinned = filtered.filter { !($0.file.pinned ?? false) }
        let grouped = unpinned.reduce(into: [String: [IngestionListItem]]()) { result, item in
            let category = panelCategory(for: item)
            result[category, default: []].append(item)
        }
        let categorized = grouped.mapValues { items in
            items.sorted(by: Self.sortByCreatedDateDescending)
        }
        let categoriesWithItems = Self.panelCategoryOrder.filter {
            categorized[$0]?.isEmpty == false
        }

        let navigationIds: [String]
        if needle.isEmpty {
            var ids = pinnedItems.filter { !panelIsFolder($0) }.map { $0.file.id }
            for category in Self.panelCategoryOrder where categorized[category] != nil {
                ids.append(
                    contentsOf: categorized[category, default: []]
                        .filter { !panelIsFolder($0) }
                        .map { $0.file.id }
                )
            }
            navigationIds = ids
        } else {
            navigationIds = searchResults.filter { !panelIsFolder($0) }.map { $0.file.id }
        }

        panelFilteredItems = filtered
        panelSearchResults = searchResults
        panelPinnedItems = pinnedItems
        panelCategorizedItems = categorized
        panelCategoriesWithItems = categoriesWithItems
        panelNavigationFileIds = navigationIds
    }

    private static func sortByCreatedDateDescending(_ lhs: IngestionListItem, _ rhs: IngestionListItem) -> Bool {
        let leftDate = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
        let rightDate = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
        return leftDate > rightDate
    }

    private static func sortPinnedItems(_ lhs: IngestionListItem, _ rhs: IngestionListItem) -> Bool {
        let leftOrder = lhs.file.pinnedOrder ?? Int.max
        let rightOrder = rhs.file.pinnedOrder ?? Int.max
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        return sortByCreatedDateDescending(lhs, rhs)
    }

    private func panelIsFolder(_ item: IngestionListItem) -> Bool {
        item.file.category == "folder"
    }

    private func panelCategory(for item: IngestionListItem) -> String {
        if let category = item.file.category, !category.isEmpty {
            return category
        }
        let normalized = item.file.mimeOriginal.split(separator: ";").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
}

import sideBarShared
import SwiftUI

extension NotesPanelView {
    func noteNavigationItems() -> [String] {
        let query = viewModel.searchQuery.trimmed
        if !query.isEmpty {
            return viewModel.searchResults.map { $0.path }
        }
        let pinnedIds = pinnedItems.map { $0.id }
        let mainIds = flattenNoteIds(from: mainNodes)
        return pinnedIds + mainIds
    }

    func flattenNoteIds(from nodes: [FileNode]) -> [String] {
        var results: [String] = []
        for node in nodes {
            if node.type == .file {
                results.append(node.path)
            }
            if let children = node.children, !children.isEmpty {
                results.append(contentsOf: flattenNoteIds(from: children))
            }
        }
        return results
    }

    var pinnedItems: [FileNodeItem] {
        let pinned = collectPinnedNodes(from: viewModel.tree?.children ?? [])
        let sorted = pinned.sorted { lhs, rhs in
            let leftOrder = lhs.pinnedOrder ?? Int.max
            let rightOrder = rhs.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return sorted.map { node in
            FileNodeItem(
                id: node.path,
                name: node.name,
                type: node.type,
                children: nil,
                pinned: node.pinned ?? true,
                archived: node.archived ?? false,
                created: node.created
            )
        }
    }

    var mainNodes: [FileNode] {
        filterNodes(viewModel.tree?.children ?? [], includeArchived: false)
    }

    var archivedNodes: [FileNode] {
        let nodes = viewModel.archivedTree?.children ?? []
        return sortNodesForDisplay(normalizeArchivedNodes(nodes))
    }

    var archivedEmptyStateText: String {
        if let count = viewModel.tree?.archivedCount {
            if count == 0 {
                return "No archived notes"
            }
        }
        if environment.isOffline || !environment.isNetworkAvailable {
            return "Archived notes are available when you're online."
        }
        return "No archived notes"
    }

    var isArchiveLoading: Bool {
        isArchiveExpanded && viewModel.isLoadingArchived
    }

    var showArchiveLoadingPlaceholder: Bool {
        isArchiveLoading && archivedNodes.isEmpty
    }

    var showArchiveEmptyState: Bool {
        !isArchiveLoading && archivedNodes.isEmpty
    }

    func normalizeArchivedNodes(_ nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { node in
            if node.type == .directory, node.name.lowercased() == "archive" {
                return node.children ?? []
            }
            return [node]
        }
    }

    func collectPinnedNodes(from nodes: [FileNode]) -> [FileNode] {
        var results: [FileNode] = []
        for node in nodes {
            if node.type == .file, node.pinned == true, node.archived != true {
                results.append(node)
            }
            if let children = node.children, !children.isEmpty {
                results.append(contentsOf: collectPinnedNodes(from: children))
            }
        }
        return results
    }

    func filterNodes(_ nodes: [FileNode], includeArchived: Bool) -> [FileNode] {
        let filtered = nodes.compactMap { node -> FileNode? in
            if node.type == .directory {
                let children = filterNodes(node.children ?? [], includeArchived: includeArchived)
                if !includeArchived && node.name.lowercased() == "archive" {
                    return nil
                }
                return FileNode(
                    name: node.name,
                    path: node.path,
                    type: node.type,
                    size: node.size,
                    modified: node.modified,
                    created: node.created,
                    children: children,
                    expanded: node.expanded,
                    pinned: node.pinned,
                    pinnedOrder: node.pinnedOrder,
                    archived: node.archived,
                    folderMarker: node.folderMarker
                )
            }
            let archived = node.archived == true
            let pinned = node.pinned == true
            if includeArchived {
                return archived ? node : nil
            }
            return (!archived && !pinned) ? node : nil
        }
        return sortNodesForDisplay(filtered)
    }

    func sortNodesForDisplay(_ nodes: [FileNode]) -> [FileNode] {
        let normalized = nodes.map { node in
            guard node.type == .directory else {
                return node
            }
            return FileNode(
                name: node.name,
                path: node.path,
                type: node.type,
                size: node.size,
                modified: node.modified,
                created: node.created,
                children: sortNodesForDisplay(node.children ?? []),
                expanded: node.expanded,
                pinned: node.pinned,
                pinnedOrder: node.pinnedOrder,
                archived: node.archived,
                folderMarker: node.folderMarker
            )
        }

        return normalized.sorted { lhs, rhs in
            let leftIsDirectory = lhs.type == .directory
            let rightIsDirectory = rhs.type == .directory
            if leftIsDirectory != rightIsDirectory {
                return leftIsDirectory
            }
            if leftIsDirectory {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            let leftRecency = lhs.created ?? 0
            let rightRecency = rhs.created ?? 0
            if leftRecency != rightRecency {
                return leftRecency > rightRecency
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

import Foundation

enum FileTreeSignature {
    static func make(_ tree: FileTree) -> [String] {
        var entries: [String] = []
        for node in tree.children {
            append(node: node, entries: &entries)
        }
        return entries.sorted()
    }

    private static func append(node: FileNode, entries: inout [String]) {
        entries.append(signature(for: node))
        if let children = node.children {
            for child in children {
                append(node: child, entries: &entries)
            }
        }
    }

    private static func signature(for node: FileNode) -> String {
        let size = node.size.map { String($0) } ?? "nil"
        let modified = node.modified.map { String($0) } ?? "nil"
        let created = node.created.map { String($0) } ?? "nil"
        let pinned = node.pinned.map { String($0) } ?? "nil"
        let pinnedOrder = node.pinnedOrder.map { String($0) } ?? "nil"
        let archived = node.archived.map { String($0) } ?? "nil"
        let folderMarker = node.folderMarker.map { String($0) } ?? "nil"
        return [
            node.name,
            node.path,
            node.type.rawValue,
            size,
            modified,
            created,
            pinned,
            pinnedOrder,
            archived,
            folderMarker
        ].joined(separator: "|")
    }
}

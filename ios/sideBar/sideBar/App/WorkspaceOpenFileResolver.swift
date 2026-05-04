import Foundation

enum WorkspaceOpenFileResolver {
    static func resolveFileID(
        request: WorkspaceEntityOpenRequest,
        items: [IngestionListItem]
    ) -> String? {
        let candidates = fileReferenceCandidates(for: request)
        guard !candidates.isEmpty else { return nil }

        if let idMatch = items.first(where: { candidates.contains($0.file.id) }) {
            return idMatch.file.id
        }
        if let pathMatch = items.first(where: { item in
            guard let path = item.file.path else { return false }
            return candidates.contains(path)
        }) {
            return pathMatch.file.id
        }
        if let filenameMatch = items.first(where: { candidates.contains($0.file.filenameOriginal) }) {
            return filenameMatch.file.id
        }
        return nil
    }

    private static func fileReferenceCandidates(
        for request: WorkspaceEntityOpenRequest
    ) -> Set<String> {
        var candidates: Set<String> = []
        insertNormalized(request.entity.id, into: &candidates)
        insertNormalized(request.entity.path, into: &candidates)
        insertNormalized(request.entity.title, into: &candidates)
        return candidates
    }

    private static func insertNormalized(_ value: String?, into candidates: inout Set<String>) {
        guard let value else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        candidates.insert(trimmed)
        candidates.insert(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

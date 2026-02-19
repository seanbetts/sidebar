import Foundation

extension TasksViewModel {
    public func updateSearch(query: String) {
        searchDebounce?.cancel()
        searchDebounce = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchQuery = ""
            guard selection.isSearch else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.load(selection: self.lastNonSearchSelection)
            }
            return
        }

        searchQuery = query
        searchDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.load(selection: .search(query: trimmed))
        }
    }

    public func clearSearchQuery() {
        searchDebounce?.cancel()
        searchDebounce = nil
        searchQuery = ""
    }
}

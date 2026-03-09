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
            guard let self else { return }
            if self.searchDebounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.searchDebounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self.load(selection: .search(query: trimmed))
        }
    }

    public func clearSearchQuery() {
        searchDebounce?.cancel()
        searchDebounce = nil
        searchQuery = ""
    }
}

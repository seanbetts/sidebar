import Foundation

extension NotesViewModel {
    func hydrateTreeFromCache() {
        store.hydrateTreeFromCache()
        tree = store.tree
    }
}

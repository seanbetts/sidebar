@preconcurrency import Foundation

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModel {
    func scheduleAutosave() {
        autosaveTask?.cancel()
        let delay = max(0.3, autosaveDelay)
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            let current = self.currentMarkdown()
            let hasChanges = current != self.lastSavedContent
            self.hasUnsavedChanges = hasChanges
            if hasChanges {
                self.autosaveToken &+= 1
            }
        }
    }

    func lastInsertedCharacter(previous: AttributedString, current: AttributedString) -> Character? {
        let prev = String(previous.characters)
        let curr = String(current.characters)
        guard curr.count == prev.count + 1 else { return nil }

        var prevIndex = prev.startIndex
        var currIndex = curr.startIndex

        while prevIndex < prev.endIndex && currIndex < curr.endIndex {
            if prev[prevIndex] != curr[currIndex] {
                return curr[currIndex]
            }
            prevIndex = prev.index(after: prevIndex)
            currIndex = curr.index(after: currIndex)
        }

        if currIndex < curr.endIndex {
            return curr[currIndex]
        }

        return nil
    }

}

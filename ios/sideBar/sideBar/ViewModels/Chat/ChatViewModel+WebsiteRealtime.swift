import Foundation
import sideBarShared

// MARK: - ChatViewModel+WebsiteRealtime

extension ChatViewModel {
    func handleWebsiteRenamed(_ event: ChatStreamEvent) {
        let id = stringValue(from: event.data, key: "id")
        refreshContext(for: .websites(id: id))
    }
}

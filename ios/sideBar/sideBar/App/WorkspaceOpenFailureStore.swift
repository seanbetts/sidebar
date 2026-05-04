import Foundation
import Combine
import sideBarShared

struct WorkspaceOpenFailure: Equatable {
    let entityType: String
    let entityID: String
    let title: String?
    let message: String

    var contextPayload: [String: AnyCodable] {
        var payload: [String: AnyCodable] = [
            "entity_type": AnyCodable(entityType),
            "entity_id": AnyCodable(entityID),
            "message": AnyCodable(message)
        ]
        if let title {
            payload["title"] = AnyCodable(title)
        }
        return payload
    }
}

@MainActor
final class WorkspaceOpenFailureStore: ObservableObject {
    @Published private(set) var latest: WorkspaceOpenFailure?

    func clear() {
        latest = nil
    }

    func record(request: WorkspaceEntityOpenRequest, message: String) {
        latest = WorkspaceOpenFailure(
            entityType: request.entity.type,
            entityID: request.entity.id,
            title: request.entity.title,
            message: message
        )
    }
}

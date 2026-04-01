import Foundation
import sideBarShared

struct TaskWidgetCompletionSyncClient {
    private let apiClient: APIClient

    init(environment: WidgetAPIEnvironment) {
        self.apiClient = environment.apiClient
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func completeTask(operation: WidgetPendingOperation<TaskWidgetAction>) async throws {
        let payload = TaskApplyRequest(
            operations: [
                TaskApplyOperation(
                    operationId: operation.id,
                    op: "complete",
                    id: operation.itemId,
                    clientUpdatedAt: nil
                )
            ]
        )
        try await apiClient.requestVoid("tasks/apply", method: "POST", body: payload)
    }
}

private struct TaskApplyRequest: Encodable {
    let operations: [TaskApplyOperation]
}

private struct TaskApplyOperation: Encodable {
    let operationId: String
    let op: String
    let id: String
    let clientUpdatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case op
        case id
        case clientUpdatedAt = "client_updated_at"
    }
}

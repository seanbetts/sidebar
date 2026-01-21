import Foundation
import Combine

// MARK: - TasksStore

/// Placeholder store for tasks feature.
///
/// Reserved for future implementation of task list management.
/// Currently provides empty reset functionality for app state cleanup.
@MainActor
public final class TasksStore: ObservableObject {
    // TODO: Wire task list + detail once TasksViewModel is implemented.
    public init() {
    }

    public func reset() {
    }
}

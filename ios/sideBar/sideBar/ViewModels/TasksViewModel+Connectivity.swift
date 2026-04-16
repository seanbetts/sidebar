import Foundation

extension TasksViewModel {
    var taskOfflineCapabilityPolicy: OfflineCapabilityPolicy {
        networkStatus.offlineCapabilityPolicy
    }

    var preferredLoadSelection: TaskSelection {
        selection == .none ? .today : selection
    }

    var shouldQueueTaskWrites: Bool {
        taskOfflineCapabilityPolicy.shouldQueueWrites
    }
}

import Foundation

extension TasksViewModel {
    var preferredLoadSelection: TaskSelection {
        selection == .none ? .today : selection
    }

    var shouldQueueTaskWrites: Bool {
        !networkStatus.isNetworkAvailable || !networkStatus.isServerReachable
    }
}

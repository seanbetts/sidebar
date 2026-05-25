import Foundation

final class WebsitesViewModelTeardownBag {
    private let lock = NSLock()
    private var transcriptPollingTasks: [String: Task<Void, Never>] = [:]
    private var jobPollingTasks: [String: Task<Void, Never>] = [:]

    func setTranscriptPollingTasks(_ tasks: [String: Task<Void, Never>]) {
        lock.lock()
        transcriptPollingTasks = tasks
        lock.unlock()
    }

    func setJobPollingTasks(_ tasks: [String: Task<Void, Never>]) {
        lock.lock()
        jobPollingTasks = tasks
        lock.unlock()
    }

    deinit {
        lock.lock()
        let transcriptPollingTasks = transcriptPollingTasks
        let jobPollingTasks = jobPollingTasks
        lock.unlock()

        for task in transcriptPollingTasks.values {
            task.cancel()
        }
        for task in jobPollingTasks.values {
            task.cancel()
        }
    }
}

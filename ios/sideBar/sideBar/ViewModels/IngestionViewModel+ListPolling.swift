import Foundation

// MARK: - IngestionViewModel+ListPolling

extension IngestionViewModel {
    func syncIngestionProgressActivities(items: [IngestionListItem]) async {
        await ingestionProgressActivityCoordinator.reconcile(items: items)
    }

    func runListPollingTick() async {
        guard allowsFallbackPolling(.files, false) else {
            stopListPolling()
            return
        }
        guard currentSyncHealth().allowsFallbackPolling else {
            stopListPolling()
            return
        }
        if isListPollRequestInFlight {
            return
        }
        if let nextAttempt = nextListPollAttemptAt, Date() < nextAttempt {
            return
        }

        isListPollRequestInFlight = true
        defer { isListPollRequestInFlight = false }

        do {
            try await store.loadList(force: true)
            listPollingConsecutiveFailures = 0
            nextListPollAttemptAt = nil
        } catch {
            listPollingConsecutiveFailures += 1
            let boundedFailures = min(listPollingConsecutiveFailures, 5)
            let exponent = Double(max(0, boundedFailures - 1))
            let backoffSeconds = min(30.0, pow(2.0, exponent))
            let jitter = Double.random(in: 0...0.6)
            nextListPollAttemptAt = Date().addingTimeInterval(backoffSeconds + jitter)
        }
    }

    func hasActiveServerBackedItems(_ items: [IngestionListItem]) -> Bool {
        items.contains { item in
            guard FileJobStatusPolicy.isActive(item.statusValue) else { return false }
            return IdentifierValidation.isServerFileID(item.file.id)
        }
    }
}

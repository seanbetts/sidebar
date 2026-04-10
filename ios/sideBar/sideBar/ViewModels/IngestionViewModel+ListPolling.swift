import Foundation

// MARK: - IngestionViewModel+ListPolling

extension IngestionViewModel {
    func syncIngestionProgressActivities(items: [IngestionListItem]) async {
        await ingestionProgressActivityCoordinator.reconcile(items: items)
    }

    func runListPollingTick() async {
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
            let status = [IngestionListItem].normalizedStatus(item.statusValue)
            guard !status.isEmpty else { return false }
            guard ![IngestionListItem].terminalStatuses.contains(status) else { return false }
            return IdentifierValidation.isServerFileID(item.file.id)
        }
    }
}

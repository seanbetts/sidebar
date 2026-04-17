import Foundation

struct RefreshTargetMetadata: Equatable {
    var lastRefreshAt: Date?
    var lastSuccessfulRefreshAt: Date?
}

@MainActor
final class RefreshMetadataStore {
    private var metadataByTarget: [RefreshTarget: RefreshTargetMetadata] = [:]

    func metadata(for target: RefreshTarget) -> RefreshTargetMetadata {
        metadataByTarget[target] ?? RefreshTargetMetadata()
    }

    func markAttempt(for targets: [RefreshTarget], at date: Date) {
        for target in targets {
            var metadata = metadata(for: target)
            metadata.lastRefreshAt = date
            metadataByTarget[target] = metadata
        }
    }

    func markSuccess(for targets: [RefreshTarget], at date: Date) {
        for target in targets {
            var metadata = metadata(for: target)
            metadata.lastRefreshAt = date
            metadata.lastSuccessfulRefreshAt = date
            metadataByTarget[target] = metadata
        }
    }

    func isStale(
        _ target: RefreshTarget,
        maxAge: TimeInterval,
        now: Date
    ) -> Bool {
        guard maxAge > 0 else {
            return true
        }

        guard let lastSuccessfulRefreshAt = metadata(for: target).lastSuccessfulRefreshAt else {
            return true
        }

        return now.timeIntervalSince(lastSuccessfulRefreshAt) >= maxAge
    }
}

import Combine
import Foundation

@MainActor
final class HeaderStatusController: ObservableObject {
    @Published private(set) var visiblePills: [HeaderStatusPillModel] = []

    private let sleepFor: @Sendable (Duration) async -> Void
    private var sessionSnapshot: HeaderSessionStatusSnapshot?
    private var syncSnapshot: HeaderSyncStatusSnapshot?
    private var ingestionSnapshot: HeaderIngestionStatusSnapshot?
    private var expiryTasks: [HeaderStatusKind: Task<Void, Never>] = [:]
    private var suppressedInformationalPillIDs: [HeaderStatusKind: String] = [:]

    convenience init(clock: some Clock<Duration> = ContinuousClock()) {
        self.init(
            sleepFor: { duration in
                try? await clock.sleep(for: duration)
            }
        )
    }

    init(sleepFor: @escaping @Sendable (Duration) async -> Void) {
        self.sleepFor = sleepFor
    }

    deinit {
        expiryTasks.values.forEach { $0.cancel() }
    }

    func applySession(snapshot: HeaderSessionStatusSnapshot?) {
        sessionSnapshot = snapshot
        updateVisibleState(for: .session)
    }

    func applySync(snapshot: HeaderSyncStatusSnapshot?) {
        syncSnapshot = snapshot
        updateVisibleState(for: .sync)
    }

    func applyIngestion(snapshot: HeaderIngestionStatusSnapshot?) {
        ingestionSnapshot = snapshot
        updateVisibleState(for: .ingestion)
    }

    private func updateVisibleState(for kind: HeaderStatusKind) {
        expiryTasks[kind]?.cancel()
        expiryTasks[kind] = nil

        let nextPill = pill(for: kind)
        if nextPill?.expiresAfter == nil || suppressedInformationalPillIDs[kind] != nextPill?.id {
            suppressedInformationalPillIDs[kind] = nil
        }

        if let pill = displayedPill(for: kind), let expiresAfter = pill.expiresAfter {
            let pillID = pill.id
            expiryTasks[kind] = Task { [weak self, sleepFor] in
                await sleepFor(expiresAfter)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.expire(kind: kind, pillID: pillID)
                }
            }
        }

        recomputeVisiblePills()
    }

    private func expire(kind: HeaderStatusKind, pillID: String) {
        guard pill(for: kind)?.id == pillID else { return }

        suppressedInformationalPillIDs[kind] = pillID
        switch kind {
        case .session:
            sessionSnapshot = nil
        case .sync:
            syncSnapshot = nil
        case .ingestion:
            ingestionSnapshot = nil
        }

        expiryTasks[kind]?.cancel()
        expiryTasks[kind] = nil
        recomputeVisiblePills()
    }

    private func recomputeVisiblePills() {
        visiblePills = HeaderStatusKind.allCases.compactMap { displayedPill(for: $0) }
    }

    private func displayedPill(for kind: HeaderStatusKind) -> HeaderStatusPillModel? {
        guard let candidate = pill(for: kind) else { return nil }
        if candidate.expiresAfter != nil, suppressedInformationalPillIDs[kind] == candidate.id {
            return nil
        }
        return candidate
    }

    private func pill(for kind: HeaderStatusKind) -> HeaderStatusPillModel? {
        switch kind {
        case .session:
            return sessionSnapshot.map(makeSessionPill)
        case .sync:
            return syncSnapshot.map(makeSyncPill)
        case .ingestion:
            return ingestionSnapshot.map(makeIngestionPill)
        }
    }

    private func makeSessionPill(snapshot: HeaderSessionStatusSnapshot) -> HeaderStatusPillModel {
        switch snapshot {
        case .reconnecting:
            return HeaderStatusPillModel(
                id: "session-reconnecting",
                kind: .session,
                tone: .progress,
                label: "Reconnecting",
                accessibilityLabel: "Reconnecting",
                isActionable: false,
                expiresAfter: nil,
                popover: HeaderStatusPopoverModel(
                    tone: .progress,
                    title: "Reconnecting",
                    message: "sideBar is reconnecting. Changes will sync automatically.",
                    rows: []
                )
            )
        case .syncPaused:
            return HeaderStatusPillModel(
                id: "session-sync-paused",
                kind: .session,
                tone: .warning,
                label: "Sync paused",
                accessibilityLabel: "Sync paused",
                isActionable: false,
                expiresAfter: nil,
                popover: HeaderStatusPopoverModel(
                    tone: .warning,
                    title: "Sync paused",
                    message: "sideBar will reconnect and sync automatically.",
                    rows: []
                )
            )
        }
    }

    private func makeSyncPill(snapshot: HeaderSyncStatusSnapshot) -> HeaderStatusPillModel {
        switch snapshot {
        case .syncing:
            return HeaderStatusPillModel(
                id: "sync-syncing",
                kind: .sync,
                tone: .progress,
                label: "Syncing",
                accessibilityLabel: "Syncing",
                isActionable: false,
                expiresAfter: nil,
                popover: HeaderStatusPopoverModel(
                    tone: .progress,
                    title: "Syncing",
                    message: "Changes are syncing now.",
                    rows: []
                )
            )
        case .pending:
            return HeaderStatusPillModel(
                id: "sync-pending",
                kind: .sync,
                tone: .warning,
                label: "Pending",
                accessibilityLabel: "Pending",
                isActionable: false,
                expiresAfter: nil,
                popover: HeaderStatusPopoverModel(
                    tone: .warning,
                    title: "Pending",
                    message: "Changes are queued and will sync automatically.",
                    rows: []
                )
            )
        case let .error(rows):
            return HeaderStatusPillModel(
                id: "sync-error-\(rows.map(\.id).joined(separator: "-"))",
                kind: .sync,
                tone: .error,
                label: "Sync error",
                accessibilityLabel: "Sync error",
                isActionable: rows.contains(where: { !$0.actions.isEmpty }),
                expiresAfter: nil,
                popover: HeaderStatusPopoverModel(
                    tone: .error,
                    title: "Sync error",
                    message: "Some changes failed to sync.",
                    rows: rows
                )
            )
        }
    }

    private func makeIngestionPill(snapshot: HeaderIngestionStatusSnapshot) -> HeaderStatusPillModel {
        switch snapshot {
        case let .active(rows):
            return HeaderStatusPillModel(
                id: "ingestion-active-\(rows.map(\.id).joined(separator: "-"))",
                kind: .ingestion,
                tone: .progress,
                label: "Processing",
                accessibilityLabel: "Processing",
                isActionable: rows.contains(where: { !$0.actions.isEmpty }),
                expiresAfter: nil,
                popover: HeaderStatusPopoverModel(
                    tone: .progress,
                    title: "Processing",
                    message: rows.count == 1 ? "1 file is still processing." : "\(rows.count) files are still processing.",
                    rows: rows
                )
            )
        case let .success(messageID, title, message):
            return HeaderStatusPillModel(
                id: messageID,
                kind: .ingestion,
                tone: .success,
                label: title,
                accessibilityLabel: title,
                isActionable: false,
                expiresAfter: .seconds(5),
                popover: HeaderStatusPopoverModel(
                    tone: .success,
                    title: title,
                    message: message,
                    rows: []
                )
            )
        case let .failureWithoutAction(messageID, title, message):
            return HeaderStatusPillModel(
                id: messageID,
                kind: .ingestion,
                tone: .error,
                label: title,
                accessibilityLabel: title,
                isActionable: false,
                expiresAfter: .seconds(5),
                popover: HeaderStatusPopoverModel(
                    tone: .error,
                    title: title,
                    message: message,
                    rows: []
                )
            )
        }
    }
}

private extension HeaderStatusKind {
    static let allCases: [HeaderStatusKind] = [.session, .sync, .ingestion]
}

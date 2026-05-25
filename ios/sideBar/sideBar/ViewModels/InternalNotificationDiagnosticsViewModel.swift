import Combine
import Foundation

/// Drives the internal notification diagnostics screen for Apple settings surfaces.
@MainActor public final class InternalNotificationDiagnosticsViewModel: ObservableObject {
    @Published public private(set) var snapshot: InternalNotificationDiagnosticsSnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSendingTestPush = false
    @Published public private(set) var isReregisteringDevice = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastTestPushResponse: InternalNotificationTestPushResponse?

    private let diagnosticsAPI: any InternalDiagnosticsProviding
    private let localStateProvider: () -> PushLifecycleDiagnosticsState
    private let reregisterCurrentDevice: () async -> Void

    public var localState: PushLifecycleDiagnosticsState {
        localStateProvider()
    }

    public init(
        diagnosticsAPI: any InternalDiagnosticsProviding,
        localStateProvider: @escaping () -> PushLifecycleDiagnosticsState,
        reregisterCurrentDevice: @escaping () async -> Void
    ) {
        self.diagnosticsAPI = diagnosticsAPI
        self.localStateProvider = localStateProvider
        self.reregisterCurrentDevice = reregisterCurrentDevice
    }

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await diagnosticsAPI.getSnapshot()
        } catch {
            errorMessage = diagnosticsErrorMessage(for: error)
        }
    }

    public func reRegisterThisDevice() async {
        isReregisteringDevice = true
        defer { isReregisteringDevice = false }
        await reregisterCurrentDevice()
    }

    public func sendTestPushToCurrentInstallation() async {
        guard let installationId = currentInstallationId else {
            errorMessage = "This device has no registered installation yet."
            return
        }

        isSendingTestPush = true
        errorMessage = nil
        defer { isSendingTestPush = false }

        do {
            lastTestPushResponse = try await diagnosticsAPI.sendTestPush(installationId: installationId)
        } catch {
            errorMessage = diagnosticsErrorMessage(for: error)
        }
    }

    public func diagnosticSummary() -> String {
        let snapshot = snapshot
        let localState = localState
        let recentDelivery = snapshot?.recentDelivery ?? []
        let recentSchedulerDecisions = snapshot?.recentSchedulerDecisions ?? []
        var lines = [
            "user_id: \(snapshot?.accountSummary?.userId ?? "unknown")",
            "can_access_internal_diagnostics: \(snapshot?.canAccessInternalDiagnostics == true)",
            "current_installation_id: \(localState.currentDeviceInstallationId ?? "unknown")",
            "current_token_suffix: \(localState.currentDeviceTokenSuffix ?? "unknown")",
            "last_registration_result: \(localState.lastDeviceRegistrationResult?.rawValue ?? "unknown")",
            "last_presence_is_foreground: \(localState.currentDevicePresenceIsForeground.map(String.init) ?? "unknown")",
            "backend_installation_count: \(snapshot?.installations.count ?? 0)",
            "recent_delivery_count: \(recentDelivery.count)",
            "scheduler_run_count: \(snapshot?.schedulerRuns.count ?? 0)",
            "recent_scheduler_decision_count: \(recentSchedulerDecisions.count)"
        ]

        if let scheduler = snapshot?.scheduler {
            lines.append("scheduler_last_status: \(scheduler.lastStatus)")
            lines.append("scheduler_last_started_at: \(scheduler.lastStartedAt ?? "unknown")")
            lines.append("scheduler_last_completed_at: \(scheduler.lastCompletedAt ?? "unknown")")
            lines.append("scheduler_task_reminders_due: \(scheduler.lastTaskRemindersDue)")
            lines.append(
                "scheduler_task_reminders_dispatched: \(scheduler.lastTaskRemindersDispatched)"
            )
            if let lastError = scheduler.lastError, !lastError.isEmpty {
                lines.append("scheduler_last_error: \(lastError)")
            }
        }

        for row in recentDelivery.prefix(5) {
            lines.append(
                "delivery[\(row.createdAt)] notification_kind=\(row.notificationKind) result=\(row.deliveryResult)"
            )
        }

        for row in recentSchedulerDecisions.prefix(5) {
            lines.append(
                "scheduler_decision[\(row.decisionStage)]: \(row.decisionReason)"
            )
        }

        return lines.joined(separator: "\n")
    }

    func replaceSnapshotForTesting(_ snapshot: InternalNotificationDiagnosticsSnapshot) {
        self.snapshot = snapshot
    }

    private var currentInstallationId: String? {
        localState.currentDeviceInstallationId
    }

    private func diagnosticsErrorMessage(for error: Error) -> String {
        let message = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Notification diagnostics failed." : message
    }
}

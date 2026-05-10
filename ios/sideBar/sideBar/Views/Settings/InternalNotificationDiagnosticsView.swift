import SwiftUI

struct InternalNotificationDiagnosticsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: InternalNotificationDiagnosticsViewModel
    @State private var copiedSummary = false

    init(viewModel: InternalNotificationDiagnosticsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section("Actions") {
                Button(viewModel.isLoading ? "Refreshing..." : "Refresh Diagnostics") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)

                Button(viewModel.isReregisteringDevice ? "Re-registering..." : "Re-register This Device") {
                    Task { await viewModel.reRegisterThisDevice() }
                }
                .disabled(viewModel.isReregisteringDevice || localState.currentDeviceTokenSuffix == nil)

                Button(viewModel.isSendingTestPush ? "Sending..." : "Send Test Push To This Installation") {
                    Task { await viewModel.sendTestPushToCurrentInstallation() }
                }
                .disabled(viewModel.isSendingTestPush || localState.currentDeviceInstallationId == nil)

                Button(copiedSummary ? "Copied" : "Copy Diagnostic Summary") {
                    SettingsDiagnosticsClipboard.copy(viewModel.diagnosticSummary())
                    copiedSummary = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedSummary = false
                    }
                }
            }

            Section("Account") {
                LabeledContent("User ID", value: snapshot?.accountSummary?.userId ?? "Unknown")
                LabeledContent(
                    "Access",
                    value: snapshot?.canAccessInternalDiagnostics == true ? "Allowed" : "Unavailable"
                )
            }

            Section("Notification State") {
                LabeledContent("Installation ID", value: localState.currentDeviceInstallationId ?? "Unknown")
                LabeledContent("Token Suffix", value: localState.currentDeviceTokenSuffix ?? "Unknown")
                LabeledContent(
                    "Last Registration Result",
                    value: localState.lastDeviceRegistrationResult?.rawValue ?? "Unknown"
                )
                LabeledContent(
                    "Foreground Presence",
                    value: localState.currentDevicePresenceIsForeground.map { $0 ? "Foreground" : "Background" } ?? "Unknown"
                )
                if let lastAttempt = localState.lastDeviceRegistrationAttemptAt {
                    LabeledContent("Last Registration Attempt", value: timestampFormatter.string(from: lastAttempt))
                }
                if let lastPresence = localState.lastDevicePresenceUpdateAt {
                    LabeledContent("Last Presence Update", value: timestampFormatter.string(from: lastPresence))
                }
            }

            Section("Scheduler") {
                if let scheduler = snapshot?.scheduler {
                    LabeledContent("Worker", value: scheduler.workerName)
                    LabeledContent("Status", value: scheduler.lastStatus)
                    LabeledContent("Task Due", value: String(scheduler.lastTaskRemindersDue))
                    LabeledContent(
                        "Task Dispatched",
                        value: String(scheduler.lastTaskRemindersDispatched)
                    )
                    if let lastStartedAt = scheduler.lastStartedAt {
                        LabeledContent("Last Started", value: lastStartedAt)
                    }
                    if let lastCompletedAt = scheduler.lastCompletedAt {
                        LabeledContent("Last Completed", value: lastCompletedAt)
                    }
                    if let lastError = scheduler.lastError, !lastError.isEmpty {
                        Text(lastError)
                            .foregroundStyle(DesignTokens.Colors.error)
                    }
                } else {
                    Text("No scheduler heartbeat yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Scheduler Runs") {
                if schedulerRuns.isEmpty {
                    Text("No scheduler run history yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(schedulerRuns.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(row.status) • due \(row.taskRemindersDue) • sent \(row.taskRemindersDispatched)")
                                .appFont(.subheading)
                            Text(row.startedAt)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            if let error = row.error, !error.isEmpty {
                                Text(error)
                                    .appFont(.caption)
                                    .foregroundStyle(DesignTokens.Colors.error)
                            }
                        }
                    }
                }
            }

            Section("Backend View") {
                if installations.isEmpty {
                    Text("No active installations.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(installations, id: \.installationId) { installation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(installation.installationId)
                                .appFont(.subheading)
                            Text(
                                "\(installation.platform) • token \(installation.tokenSuffix ?? "unknown") • " +
                                "\(installation.isForeground == true ? "foreground" : "background")"
                            )
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Recent Delivery") {
                if recentDelivery.isEmpty {
                    Text("No recent delivery audit rows.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(recentDelivery.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(row.notificationKind) • \(row.deliveryResult)")
                                .appFont(.subheading)
                            Text(row.createdAt)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            if let reason = row.apnsReason ?? row.skipReason {
                                Text(reason)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Scheduler Decisions") {
                if recentSchedulerDecisions.isEmpty {
                    Text("No recent scheduler decision rows.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(recentSchedulerDecisions.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(row.decisionStage) • \(row.decisionReason)")
                                .appFont(.subheading)
                            Text(row.createdAt)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            if let detail = row.detail, !detail.isEmpty {
                                Text(detail)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }

            if let lastTestPushResponse = viewModel.lastTestPushResponse {
                Section("Last Test Push") {
                    LabeledContent("Installation", value: lastTestPushResponse.installationId)
                    LabeledContent("Accepted", value: lastTestPushResponse.accepted ? "Yes" : "No")
                    if let message = lastTestPushResponse.message, !message.isEmpty {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Notification Diagnostics")
        .task {
            if viewModel.snapshot == nil {
                await viewModel.refresh()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var localState: PushLifecycleDiagnosticsState {
        viewModel.localState
    }

    private var snapshot: InternalNotificationDiagnosticsSnapshot? {
        viewModel.snapshot
    }

    private var installations: [NotificationDiagnosticsInstallationRow] {
        snapshot?.installations ?? []
    }

    private var recentDelivery: [NotificationDiagnosticsDeliveryAuditRow] {
        snapshot?.recentDelivery ?? []
    }

    private var schedulerRuns: [NotificationDiagnosticsSchedulerRunRow] {
        snapshot?.schedulerRuns ?? []
    }

    private var recentSchedulerDecisions: [NotificationSchedulerDecisionRow] {
        snapshot?.recentSchedulerDecisions ?? []
    }

    private var errorMessage: String? {
        viewModel.errorMessage
    }

    private var timestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }
}

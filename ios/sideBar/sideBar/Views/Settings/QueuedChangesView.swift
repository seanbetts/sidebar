import SwiftUI
import OSLog

struct QueuedChangesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var queuedChanges: [PendingWriteSummary] = []
    private let logger = Logger(subsystem: "sideBar", category: "QueuedChangesView")

    var body: some View {
        List {
            if queuedChanges.isEmpty {
                ContentUnavailableView(
                    "All Synced",
                    systemImage: "checkmark.circle",
                    description: Text("No queued changes")
                )
            } else {
                ForEach(queuedChanges) { queuedChange in
                    QueuedChangeRow(queuedChange: queuedChange) { resolution in
                        Task {
                            await environment.writeQueue.resolveConflict(id: queuedChange.id, resolution: resolution)
                            await reloadQueuedChanges()
                        }
                    }
                }
                .onDelete(perform: deleteQueuedChanges)
            }
        }
        .navigationTitle("Queued Changes")
        .toolbar {
            if !queuedChanges.isEmpty {
                Button("Retry All") {
                    Task {
                        await environment.writeQueue.processQueue()
                        await reloadQueuedChanges()
                    }
                }
            }
            if shouldShowDropOldest {
                Button("Drop Oldest") {
                    Task {
                        await environment.writeQueue.pruneOldestWrites(
                            keeping: environment.writeQueue.maxPendingWrites
                        )
                        await reloadQueuedChanges()
                    }
                }
            }
        }
        .task {
            await reloadQueuedChanges()
        }
    }

    private func reloadQueuedChanges() async {
        do {
            queuedChanges = try await environment.writeQueue.fetchPendingWrites()
        } catch {
            logger.error("Failed to reload queued changes: \(error.localizedDescription, privacy: .public)")
            queuedChanges = []
        }
    }

    private func deleteQueuedChanges(at offsets: IndexSet) {
        let ids = offsets.map { queuedChanges[$0].id }
        Task {
            await environment.writeQueue.deleteWrites(ids: ids)
            await reloadQueuedChanges()
        }
    }

    private var shouldShowDropOldest: Bool {
        environment.writeQueue.pendingCount >= environment.writeQueue.maxPendingWrites
    }
}

private struct QueuedChangeRow: View {
    let queuedChange: PendingWriteSummary
    let onResolveQueuedChange: (WriteQueueConflictResolution) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                Text(titleText)
                    .appFont(.labelMd)
                Spacer()
                Text(statusText)
                    .appFont(.captionSemibold)
                    .foregroundStyle(statusColor)
            }
            if let conflictReason = queuedChange.conflictReason {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(conflictReason)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Keep Queued Change") {
                        onResolveQueuedChange(.keepLocal)
                    }
                    .buttonStyle(PendingWriteActionButtonStyle())
                    Button("Use Server Version") {
                        onResolveQueuedChange(.keepServer)
                    }
                    .buttonStyle(PendingWriteActionButtonStyle())
                }
            }
            if queuedChange.conflictReason == nil, let error = queuedChange.lastError {
                Text(error)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
            Text("Attempts: \(queuedChange.attempts)")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private var titleText: String {
        let entity = queuedChange.entityType.capitalized
        let operation = queuedChange.operationType.capitalized
        return "\(operation) \(entity)"
    }

    private var iconName: String {
        switch queuedChange.entityType {
        case "note":
            return "note.text"
        case "message":
            return "bubble.left.and.bubble.right"
        case "website":
            return "globe"
        case "file":
            return "doc"
        case "scratchpad":
            return "square.and.pencil"
        default:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var statusText: String {
        if queuedChange.conflictReason != nil {
            return "Needs Review"
        }
        return queuedChange.status.capitalized
    }

    private var statusColor: Color {
        if queuedChange.conflictReason != nil {
            return DesignTokens.Colors.error
        }
        switch queuedChange.status {
        case WriteQueueStatus.failed.rawValue:
            return DesignTokens.Colors.error
        case WriteQueueStatus.inProgress.rawValue:
            return DesignTokens.Colors.success
        default:
            return DesignTokens.Colors.warning
        }
    }
}

private struct PendingWriteActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(.captionSemibold)
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(DesignTokens.Colors.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: DesignTokens.Animation.quick), value: configuration.isPressed)
    }
}

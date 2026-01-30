import SwiftUI

struct PendingWritesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var pendingWrites: [PendingWriteSummary] = []

    var body: some View {
        List {
            if pendingWrites.isEmpty {
                ContentUnavailableView(
                    "All Synced",
                    systemImage: "checkmark.circle",
                    description: Text("No pending changes")
                )
            } else {
                ForEach(pendingWrites) { write in
                    PendingWriteRow(write: write)
                }
                .onDelete(perform: deletePendingWrites)
            }
        }
        .navigationTitle("Pending Changes")
        .toolbar {
            if !pendingWrites.isEmpty {
                Button("Retry All") {
                    Task {
                        await environment.writeQueue.processQueue()
                        await reloadPendingWrites()
                    }
                }
            }
            if shouldShowDropOldest {
                Button("Drop Oldest") {
                    Task {
                        await environment.writeQueue.pruneOldestWrites(
                            keeping: environment.writeQueue.maxPendingWrites
                        )
                        await reloadPendingWrites()
                    }
                }
            }
        }
        .task {
            await reloadPendingWrites()
        }
    }

    private func reloadPendingWrites() async {
        pendingWrites = await environment.writeQueue.fetchPendingWrites()
    }

    private func deletePendingWrites(at offsets: IndexSet) {
        let ids = offsets.map { pendingWrites[$0].id }
        Task {
            await environment.writeQueue.deleteWrites(ids: ids)
            await reloadPendingWrites()
        }
    }

    private var shouldShowDropOldest: Bool {
        environment.writeQueue.pendingCount >= environment.writeQueue.maxPendingWrites
    }
}

private struct PendingWriteRow: View {
    let write: PendingWriteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                Text(titleText)
                    .font(DesignTokens.Typography.labelMd)
                Spacer()
                Text(statusText)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(statusColor)
            }
            if let error = write.lastError {
                Text(error)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
            Text("Attempts: \(write.attempts)")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private var titleText: String {
        let entity = write.entityType.capitalized
        let operation = write.operationType.capitalized
        return "\(operation) \(entity)"
    }

    private var iconName: String {
        switch write.entityType {
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
        write.status.capitalized
    }

    private var statusColor: Color {
        switch write.status {
        case WriteQueueStatus.failed.rawValue:
            return DesignTokens.Colors.error
        case WriteQueueStatus.inProgress.rawValue:
            return DesignTokens.Colors.success
        default:
            return DesignTokens.Colors.warning
        }
    }
}

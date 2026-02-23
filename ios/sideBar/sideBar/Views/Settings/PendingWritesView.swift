import SwiftUI
import OSLog

struct PendingWritesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var pendingWrites: [PendingWriteSummary] = []
    private let logger = Logger(subsystem: "sideBar", category: "PendingWritesView")

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
                    PendingWriteRow(write: write) { resolution in
                        Task {
                            await environment.writeQueue.resolveConflict(id: write.id, resolution: resolution)
                            await reloadPendingWrites()
                        }
                    }
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
        do {
            pendingWrites = try await environment.writeQueue.fetchPendingWrites()
        } catch {
            logger.error("Failed to reload pending writes: \(error.localizedDescription, privacy: .public)")
            pendingWrites = []
        }
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
    let onResolveConflict: (WriteQueueConflictResolution) -> Void

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
            if let conflictReason = write.conflictReason {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(conflictReason)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Keep Local") {
                        onResolveConflict(.keepLocal)
                    }
                    .buttonStyle(PendingWriteActionButtonStyle())
                    Button("Keep Server") {
                        onResolveConflict(.keepServer)
                    }
                    .buttonStyle(PendingWriteActionButtonStyle())
                }
            }
            if write.conflictReason == nil, let error = write.lastError {
                Text(error)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
            Text("Attempts: \(write.attempts)")
                .appFont(.caption)
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
        if write.conflictReason != nil {
            return "Conflict"
        }
        return write.status.capitalized
    }

    private var statusColor: Color {
        if write.conflictReason != nil {
            return DesignTokens.Colors.error
        }
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

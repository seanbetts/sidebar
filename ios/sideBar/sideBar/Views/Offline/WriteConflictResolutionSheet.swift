import SwiftUI

struct WriteConflictResolutionSheet: View {
    let conflict: PendingWriteSummary
    let onResolve: (WriteQueueConflictResolution) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Resolve Sync Conflict")
                        .font(DesignTokens.Typography.title3Semibold)
                    Text(subtitleText)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.secondary)
                }

                detailsCard

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button("Keep Local") {
                        onResolve(.keepLocal)
                    }
                    .buttonStyle(.bordered)

                    Button("Keep Server") {
                        onResolve(.keepServer)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .navigationTitle("Conflict")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            detailRow(title: "Change", value: operationLabel)
            detailRow(title: "Item", value: entityLabel)
            detailRow(title: "Queued", value: conflict.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let conflictReason = conflict.conflictReason {
                Text(conflictReason)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.primary)
        }
    }

    private var subtitleText: String {
        if let reason = conflict.conflictReason {
            return reason
        }
        return "This change couldn’t sync because the server has newer data."
    }

    private var operationLabel: String {
        conflict.operationType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var entityLabel: String {
        conflict.entityType.capitalized
    }
}

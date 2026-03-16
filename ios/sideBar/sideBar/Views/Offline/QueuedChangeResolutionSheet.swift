import SwiftUI

struct QueuedChangeResolutionSheet: View {
    let queuedChange: PendingWriteSummary
    let onResolveQueuedChange: (WriteQueueConflictResolution) -> Void

    var body: some View {
        MacModalShell(type: queuedChangeResolutionPanelType()) {
            NavigationStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    header

                    if let subtitleText {
                        Text(subtitleText)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                    detailContent
                    Divider()
                    actionsRow
                }
                .padding(DesignTokens.Spacing.lg)
                .navigationTitle("Queued Change")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .appFont(.subheadlineSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("Resolve Queued Change")
                .appFont(.title3Semibold)
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("\(operationLabel) \(entityLabel)")
                .appFont(.subheadlineSemibold)
                .foregroundStyle(.primary)
            Text("Queued \(queuedChange.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .appFont(.caption)
                .foregroundStyle(.secondary)
            if let conflictReason = queuedChange.conflictReason {
                Text(conflictReason)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .lineLimit(2)
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Spacer(minLength: 0)
            Button("Keep Queued Change") {
                onResolveQueuedChange(.keepLocal)
            }
            .buttonStyle(ConflictActionButtonStyle())
            Button("Use Server Version") {
                onResolveQueuedChange(.keepServer)
            }
            .buttonStyle(ConflictActionButtonStyle())
        }
    }

    private var subtitleText: String? {
        queuedChange.conflictReason == nil
            ? "This queued change couldn't sync because the server has newer data."
            : nil
    }

    private var operationLabel: String {
        queuedChange.operationType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var entityLabel: String {
        queuedChange.entityType.capitalized
    }
}

private struct ConflictActionButtonStyle: ButtonStyle {
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

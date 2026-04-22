import SwiftUI

struct QueuedChangeResolutionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let queuedChange: PendingWriteSummary

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
                .navigationTitle("Sync Issue")
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
            Text("Review Sync Issue")
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
            Button("Done") {
                dismiss()
            }
            .buttonStyle(ConflictActionButtonStyle())
        }
    }

    private var subtitleText: String? {
        if let conflictReason = queuedChange.conflictReason,
           !conflictReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return conflictReason
        }

        return "Retry or cancel this change from queued changes."
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

import SwiftUI

struct WriteConflictResolutionSheet: View {
    let conflict: PendingWriteSummary
    let onResolve: (WriteQueueConflictResolution) -> Void

    var body: some View {
        MacModalShell(type: writeConflictPanelType()) {
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
                .navigationTitle("Conflict")
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
            Text("Resolve Sync Conflict")
                .appFont(.title3Semibold)
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("\(operationLabel) \(entityLabel)")
                .appFont(.subheadlineSemibold)
                .foregroundStyle(.primary)
            Text("Queued \(conflict.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .appFont(.caption)
                .foregroundStyle(.secondary)
            if let conflictReason = conflict.conflictReason {
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
            Button("Keep Local") {
                onResolve(.keepLocal)
            }
            .buttonStyle(ConflictActionButtonStyle())
            Button("Keep Server") {
                onResolve(.keepServer)
            }
            .buttonStyle(ConflictActionButtonStyle())
        }
    }

    private var subtitleText: String? {
        conflict.conflictReason == nil
            ? "This change couldn’t sync because the server has newer data."
            : nil
    }

    private var operationLabel: String {
        conflict.operationType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var entityLabel: String {
        conflict.entityType.capitalized
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

import SwiftUI

struct MorningDigestView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    digestHeader
                    digestTaskSummary
                    digestActions
                }
                .padding(DesignTokens.Spacing.lg)
            }
            .background(DesignTokens.Colors.settingsBackground)
            .navigationTitle("Morning Digest")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await environment.tasksViewModel.loadCounts(force: true)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var digestHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("A calm start for today.")
                .appFont(.titleMd)
            Text("Morning digest keeps the notification short, then gives you a dedicated place to review the day’s task snapshot.")
                .appFont(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var digestTaskSummary: some View {
        let counts = environment.tasksViewModel.counts?.counts
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Task snapshot")
                .appFont(.subheading)

            HStack(spacing: DesignTokens.Spacing.md) {
                digestMetric(label: "Today", value: counts?.today ?? 0)
                digestMetric(label: "Upcoming", value: counts?.upcoming ?? 0)
                digestMetric(label: "Completed", value: counts?.completed ?? 0)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
    }

    private var digestActions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Quick actions")
                .appFont(.subheading)

            Button {
                dismiss()
                if let url = URL(string: "sidebar://tasks/today") {
                    environment.handleDeepLink(url)
                }
            } label: {
                Label("Open tasks for today", systemImage: "checklist")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func digestMetric(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("\(value)")
                .appFont(.titleSm)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

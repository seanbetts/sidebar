import SwiftUI

struct ConflictResolutionSheet: View {
    let conflict: NoteSyncConflict
    let onResolve: (NoteConflictChoice) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.lg) {
                Text("This note was edited in multiple places")
                    .font(DesignTokens.Typography.title3Semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: DesignTokens.Spacing.md) {
                    conflictColumn(
                        title: "Your Version",
                        date: conflict.localDate,
                        content: conflict.localContent,
                        accent: DesignTokens.Colors.warning
                    ) {
                        onResolve(.keepLocal)
                    }

                    conflictColumn(
                        title: "Server Version",
                        date: conflict.serverDate,
                        content: conflict.serverContent,
                        accent: DesignTokens.Colors.success
                    ) {
                        onResolve(.keepServer)
                    }
                }
                .frame(maxWidth: .infinity)

                Button("Keep Both (Create Copy)") {
                    onResolve(.keepBoth)
                }
                .buttonStyle(.bordered)
            }
            .padding(DesignTokens.Spacing.lg)
            .navigationTitle("Resolve Conflict")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    @ViewBuilder
    private func conflictColumn(
        title: String,
        date: Date,
        content: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.labelLg)
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(content)
                    .font(DesignTokens.Typography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(DesignTokens.Spacing.sm)
            .background(accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))

            Button("Select") {
                action()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}

enum NoteConflictChoice {
    case keepLocal
    case keepServer
    case keepBoth
}

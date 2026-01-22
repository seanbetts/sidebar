import SwiftUI

public struct TasksView: View {
    public init() {
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(DesignTokens.Typography.titleLg)
                .foregroundStyle(.secondary)
            Text("Tasks")
                .font(.headline)
            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your tasks will appear here.")
                .font(DesignTokens.Typography.subheadlineSemibold)
            Text("Create tasks in sideBar to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

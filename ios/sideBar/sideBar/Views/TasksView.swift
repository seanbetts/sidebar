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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Tasks")
                .font(.headline)
            Spacer()
        }
        .padding(16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Things integration will appear here.")
                .font(.subheadline.weight(.semibold))
            Text("Install Things on this device to view your tasks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

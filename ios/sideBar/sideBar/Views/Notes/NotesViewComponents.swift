import SwiftUI
import sideBarShared

struct FolderOption: Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
    let depth: Int

    static func build(from nodes: [FileNode]) -> [FolderOption] {
        var options: [FolderOption] = [
            FolderOption(id: "", label: "Notes", value: "", depth: 0)
        ]

        func walk(_ items: [FileNode], depth: Int) {
            for item in items {
                guard item.type == .directory else { continue }
                if item.name.lowercased() == "archive" { continue }
                let folderPath = item.path.replacingOccurrences(of: "folder:", with: "")
                options.append(
                    FolderOption(
                        id: folderPath,
                        label: item.name,
                        value: folderPath,
                        depth: depth
                    )
                )
                if let children = item.children, !children.isEmpty {
                    walk(children, depth: depth + 1)
                }
            }
        }

        walk(nodes, depth: 1)
        return options
    }
}

struct NoteFolderPickerSheet: View {
    let title: String
    @Binding var selection: String
    let options: [FolderOption]
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery: String = ""

    var body: some View {
        #if os(macOS)
        MacModalShell(type: .chooserSheet) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(title)
                        .appFont(.title3Semibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("Choose the folder that should contain this note.")
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                if options.count > 8 {
                    SearchField(text: $searchQuery, placeholder: "Search folders")
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        ForEach(filteredOptions) { option in
                            Button {
                                selection = option.value
                            } label: {
                                HStack(spacing: DesignTokens.Spacing.sm) {
                                    Text(optionLabel(option))
                                        .appFont(.body)
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if selection == option.value {
                                        Image(systemName: "checkmark")
                                            .appFont(.captionSemibold)
                                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                                    }
                                }
                                .padding(.horizontal, DesignTokens.Spacing.sm)
                                .padding(.vertical, DesignTokens.Spacing.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                                        .fill(
                                            selection == option.value
                                                ? DesignTokens.Colors.muted
                                                : DesignTokens.Colors.surface
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                                        .stroke(DesignTokens.Colors.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Move") {
                        onConfirm(selection)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(options.isEmpty)
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .frame(minHeight: 360, idealHeight: 420)
        }
        #else
        NavigationStack {
            List(options) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack {
                        Text(optionLabel(option))
                        Spacer()
                        if selection == option.value {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accent)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        onConfirm(selection)
                        dismiss()
                    }
                    .disabled(options.isEmpty)
                }
            }
        }
        #endif
    }

    private func optionLabel(_ option: FolderOption) -> String {
        let indent = String(repeating: "  ", count: max(0, option.depth))
        return indent + option.label
    }

    private var filteredOptions: [FolderOption] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { option in
            option.label.localizedCaseInsensitiveContains(query)
        }
    }
}

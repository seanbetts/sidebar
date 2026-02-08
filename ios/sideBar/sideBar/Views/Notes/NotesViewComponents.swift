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

    var body: some View {
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
    }

    private func optionLabel(_ option: FolderOption) -> String {
        let indent = String(repeating: "  ", count: max(0, option.depth))
        return indent + option.label
    }
}

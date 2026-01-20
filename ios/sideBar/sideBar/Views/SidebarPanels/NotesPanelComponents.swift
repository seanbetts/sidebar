import Foundation
import SwiftUI

struct NotesFolderOption: Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
    let depth: Int

    static func build(from nodes: [FileNode]) -> [NotesFolderOption] {
        var options: [NotesFolderOption] = [
            NotesFolderOption(id: "", label: "Notes", value: "", depth: 0)
        ]

        func walk(_ items: [FileNode], depth: Int) {
            for item in items {
                guard item.type == .directory else { continue }
                if item.name.lowercased() == "archive" { continue }
                let folderPath = item.path.replacingOccurrences(of: "folder:", with: "")
                options.append(
                    NotesFolderOption(
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

struct NewFolderSheet: View {
    @Binding var name: String
    @Binding var selectedFolder: String
    let options: [NotesFolderOption]
    let isSaving: Bool
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder") {
                    TextField("Folder name", text: $name)
                        .submitLabel(.done)
                        .onSubmit {
                            onCreate()
                        }
                        .focused($isNameFocused)
                }
                Section("Location") {
                    Picker("Location", selection: $selectedFolder) {
                        ForEach(options) { option in
                            Text(optionLabel(option))
                                .tag(option.value)
                        }
                    }
                }
            }
            .navigationTitle("New Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate()
                    }
                    .disabled(isSaving || name.trimmed.isEmpty)
                }
            }
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private func optionLabel(_ option: NotesFolderOption) -> String {
        let indent = String(repeating: "  ", count: max(0, option.depth))
        return indent + option.label
    }
}

struct NotesTreeRow: View {
    let item: FileNodeItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: (() -> Void)?
    let onDelete: (() -> Void)?
    let useListStyling: Bool

    init(
        item: FileNodeItem,
        isSelected: Bool,
        useListStyling: Bool = true,
        onSelect: @escaping () -> Void,
        onRename: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.useListStyling = useListStyling
        self.onSelect = onSelect
        self.onRename = onRename
        self.onDelete = onDelete
    }

    var body: some View {
        let row = SelectableRow(
            isSelected: isSelected,
            insets: rowInsets,
            verticalPadding: rowVerticalPadding,
            useListStyling: useListStyling
        ) {
            HStack(spacing: 8) {
                Image(systemName: item.isFile ? "doc.text" : "folder")
                    .foregroundStyle(isSelected ? selectedTextColor : (item.isFile ? secondaryTextColor : primaryTextColor))
                Text(item.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
            }
        }

        Group {
            if item.isFile {
                row.onTapGesture {
                    onSelect()
                }
            } else {
                row
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onRename {
                Button("Rename") {
                    onRename()
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onDelete {
                Button("Delete") {
                    onDelete()
                }
                .tint(.red)
            }
        }
        #endif
    }

    private var primaryTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private var selectedTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }

    private var rowInsets: EdgeInsets {
        let horizontalPadding: CGFloat
        #if os(macOS)
        horizontalPadding = DesignTokens.Spacing.xs
        #else
        horizontalPadding = item.isFile ? DesignTokens.Spacing.sm : DesignTokens.Spacing.xs
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }

    private var rowVerticalPadding: CGFloat {
        #if os(macOS)
        return DesignTokens.Spacing.xs
        #else
        return item.isFile ? DesignTokens.Spacing.xs : DesignTokens.Spacing.xxs
        #endif
    }
}

struct FileNodeItem: Identifiable {
    let id: String
    let name: String
    let type: FileNodeType
    let children: [FileNodeItem]?

    var isFile: Bool { type == .file }

    var displayName: String {
        if isFile, name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }
}

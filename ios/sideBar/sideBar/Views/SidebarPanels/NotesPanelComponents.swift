import Foundation
import sideBarShared
import SwiftUI

// MARK: - NotesPanelComponents

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
                    .appFont(.body)
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
            useListStyling: useListStyling,
            primaryAction: primaryAction
        ) {
            HStack(spacing: 8) {
                Image(systemName: item.isFile ? "doc.text" : "folder")
                    .foregroundStyle(isSelected ? selectedTextColor : (item.isFile ? secondaryTextColor : primaryTextColor))
                if item.isFile {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .appFont(SidebarTypography.primary)
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                        if let dateText = item.formattedCreatedDate {
                            Text(dateText)
                                .appFont(SidebarTypography.secondary)
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? selectedSecondaryText : secondaryTextColor)
                        }
                    }
                } else {
                    Text(item.displayName)
                        .appFont(SidebarTypography.primary)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                }
            }
        }

        Group {
            row
        }
        #if os(macOS)
        .sidebarListSwipeActions(
            leadingTitle: onRename == nil ? nil : "Rename",
            onLeading: onRename,
            onDelete: onDelete
        )
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

    private var selectedSecondaryText: Color {
        DesignTokens.Colors.textSecondary
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
        horizontalPadding = DesignTokens.Spacing.sm
        #else
        horizontalPadding = item.isFile ? DesignTokens.Spacing.smPlus : DesignTokens.Spacing.sm
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

    private var primaryAction: (() -> Void)? {
        guard item.isFile else { return nil }
        #if os(macOS)
        return nil
        #else
        return onSelect
        #endif
    }
}

struct FileNodeItem: Identifiable {
    let id: String
    let name: String
    let type: FileNodeType
    let children: [FileNodeItem]?
    let pinned: Bool
    let archived: Bool
    let created: Double?

    init(
        id: String,
        name: String,
        type: FileNodeType,
        children: [FileNodeItem]? = nil,
        pinned: Bool = false,
        archived: Bool = false,
        created: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.children = children
        self.pinned = pinned
        self.archived = archived
        self.created = created
    }

    var isFile: Bool { type == .file }

    var displayName: String {
        return name
    }

    var formattedCreatedDate: String? {
        guard let created else { return nil }
        let date = Date(timeIntervalSince1970: created)
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

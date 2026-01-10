import SwiftUI

public struct ConversationsPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        ConversationsPanelView(viewModel: environment.chatViewModel)
            .task {
                await environment.chatViewModel.loadConversations()
            }
    }
}

private struct ConversationsPanelView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingConversations && viewModel.conversations.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading conversations…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.conversations.isEmpty {
                SidebarPanelPlaceholder(title: "No conversations")
            } else {
                List {
                    ForEach(viewModel.groupedConversations) { group in
                        Section(group.title) {
                            ForEach(group.conversations) { conversation in
                                Button {
                                    Task { await viewModel.selectConversation(id: conversation.id) }
                                } label: {
                                    ConversationRow(
                                        conversation: conversation,
                                        isSelected: viewModel.selectedConversationId == conversation.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(rowBackground(isSelected: viewModel.selectedConversationId == conversation.id))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .refreshable {
                    await viewModel.refreshConversations()
                }
            }
        }
    }

    private func rowBackground(isSelected: Bool) -> Color {
        guard isSelected else {
            return Color.clear
        }
        #if os(macOS)
        return Color(nsColor: .selectedContentBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conversation.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .primary : .primary)
                .lineLimit(1)
            if let preview = conversation.firstMessage, !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(formattedDate)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var formattedDate: String {
        guard let date = DateParsing.parseISO8601(conversation.updatedAt) else {
            return conversation.updatedAt
        }
        return DateFormatter.chatList.string(from: date)
    }
}

private extension DateFormatter {
    static let chatList: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

public struct NotesPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        NotesPanelView(viewModel: environment.notesViewModel)
    }
}

private struct NotesPanelView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if viewModel.tree == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    OutlineGroup(buildItems(from: viewModel.tree?.children ?? []), children: \.children) { item in
                        NotesTreeRow(
                            item: item,
                            isSelected: viewModel.selectedNoteId == item.id
                        ) {
                            if item.isFile {
                                Task { await viewModel.selectNote(id: item.id) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .refreshable {
                    await viewModel.loadTree()
                }
            }
        }
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.loadTree() }
            }
        }
    }

    private func buildItems(from nodes: [FileNode]) -> [FileNodeItem] {
        nodes.map { node in
            FileNodeItem(
                id: node.path,
                name: node.name,
                type: node.type,
                children: buildItems(from: node.children ?? [])
            )
        }
    }
}

private struct NotesTreeRow: View {
    let item: FileNodeItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: item.isFile ? "doc.text" : "folder")
                    .foregroundStyle(item.isFile ? .secondary : .primary)
                Text(item.displayName)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? selectionBackground : Color.clear)
    }

    private var selectionBackground: Color {
        #if os(macOS)
        return Color(nsColor: .selectedContentBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private struct FileNodeItem: Identifiable {
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

public struct FilesPanel: View {
    public init() {
    }

    public var body: some View {
        SidebarPanelPlaceholder(title: "Files")
    }
}

public struct WebsitesPanel: View {
    public init() {
    }

    public var body: some View {
        SidebarPanelPlaceholder(title: "Websites")
    }
}

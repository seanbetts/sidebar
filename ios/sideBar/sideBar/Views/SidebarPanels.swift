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
    public init() {
    }

    public var body: some View {
        SidebarPanelPlaceholder(title: "Notes")
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

import SwiftUI

struct ChatHeaderView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.workspaceColumn) private var workspaceColumn
    @AppStorage(AppStorageKeys.workspaceExpanded) private var isWorkspaceExpanded: Bool = false
    #if os(iOS)
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) private var isWorkspaceExpandedByRotation: Bool = false
    #endif
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        if showExtendedContent {
            VStack(alignment: .leading, spacing: 6) {
                headerContent

                if let activeTool = viewModel.activeTool {
                    ChatActiveToolBanner(activeTool: activeTool)
                }

                if let promptPreview = viewModel.promptPreview {
                    PromptPreviewView(promptPreview: promptPreview)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(minHeight: LayoutMetrics.contentHeaderMinHeight)
            .background(headerBackground)
        } else {
            headerContent
                .padding(DesignTokens.Spacing.md)
                .frame(height: LayoutMetrics.contentHeaderMinHeight)
                .background(headerBackground)
        }
    }

    private var showExtendedContent: Bool {
        if isCompact {
            return false
        }
        return viewModel.activeTool != nil ||
            viewModel.promptPreview != nil
    }

    private var headerContent: some View {
        ContentHeaderRow(
            iconName: "bubble",
            title: selectedTitle,
            titleLineLimit: 1
        , trailing: {
            HStack(spacing: 12) {
                if viewModel.isStreaming {
                    Label("Streaming", systemImage: "dot.radiowaves.left.and.right")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                if showNewChatButton || showCloseButton {
                    HeaderActionRow {
                        if shouldShowExpandButton {
                            expandButton
                        }
                        if showNewChatButton {
                            HeaderActionButton(
                                systemName: "plus",
                                accessibilityLabel: "New chat",
                                action: {
                                    Task {
                                        await viewModel.startNewConversation()
                                    }
                                }
                            )
                        }
                        if showCloseButton {
                            HeaderActionButton(
                                systemName: "xmark",
                                accessibilityLabel: "Close chat",
                                action: {
                                    Task {
                                        await viewModel.closeConversation()
                                    }
                                }
                            )
                        }
                    }
                }
            }
        })
    }

    private var selectedTitle: String {
        guard let selectedId = viewModel.selectedConversationId,
              let conversation = viewModel.conversations.first(where: { $0.id == selectedId }) else {
            return "New Chat"
        }
        return conversation.title
    }

    private var showNewChatButton: Bool {
        guard viewModel.selectedConversationId != nil else {
            return false
        }
        return !viewModel.isBlankConversation
    }

    private var showCloseButton: Bool {
        viewModel.selectedConversationId != nil
    }

    private var headerBackground: Color {
        DesignTokens.Colors.background
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var shouldShowExpandButton: Bool {
        guard workspaceColumn == .primary else { return false }
        #if os(iOS)
        return !isPhone
        #else
        return true
        #endif
    }

    private var expandButton: some View {
        Button(action: expandChatView) {
            Image(systemName: expandButtonIconName)
                .font(DesignTokens.Typography.labelMd)
                .frame(width: 28, height: 20)
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expandButtonLabel)
    }

    private var expandButtonIconName: String {
        isWorkspaceExpanded ? "arrow.up.right.and.arrow.down.left" : "arrow.down.left.and.arrow.up.right"
    }

    private var expandButtonLabel: String {
        isWorkspaceExpanded ? "Exit expanded mode" : "Expand chat"
    }

    private func expandChatView() {
        #if os(iOS)
        if !isPhone {
            isWorkspaceExpandedByRotation = false
        }
        #endif
        isWorkspaceExpanded.toggle()
    }

    #if os(iOS)
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif
}

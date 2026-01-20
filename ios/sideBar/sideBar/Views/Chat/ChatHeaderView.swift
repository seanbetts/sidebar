import SwiftUI

struct ChatHeaderView: View {
    @ObservedObject var viewModel: ChatViewModel
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        if showExtendedContent {
            VStack(alignment: .leading, spacing: 6) {
                headerContent

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }

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
        return viewModel.errorMessage != nil ||
            viewModel.activeTool != nil ||
            viewModel.promptPreview != nil
    }

    private var headerContent: some View {
        ContentHeaderRow(
            iconName: "bubble",
            title: selectedTitle,
            titleLineLimit: 1
        ) {
            HStack(spacing: 12) {
                if viewModel.isStreaming {
                    Label("Streaming", systemImage: "dot.radiowaves.left.and.right")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                if showNewChatButton || showCloseButton {
                    HeaderActionRow {
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
        }
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
}

import SwiftUI
import UniformTypeIdentifiers
import sideBarShared

enum ChatConversationActionsSurface {
    case header
    case toolbar
}

struct ChatConversationActionsMenu: View {
    @ObservedObject var viewModel: ChatViewModel
    let surface: ChatConversationActionsSurface
    var chromeStyle: HeaderActionControlChromeStyle = .plain
    @EnvironmentObject private var environment: AppEnvironment
    @State private var exportDocument: PlainTextFileDocument?
    @State private var exportFilename = "Chat.txt"
    @State private var isExporting = false

    var body: some View {
        actionControl
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .plainText,
                defaultFilename: exportFilename
            ) { _ in
                exportDocument = nil
            }
    }

    @ViewBuilder
    private var actionControl: some View {
        #if os(macOS)
        Menu {
            actionButtons
        } label: {
            HeaderActionIcon(icon: AppIcon.Action.more)
                .headerActionControlChrome(chromeStyle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat options")
        #else
        switch surface {
        case .header:
            HeaderActionMenuButton(
                icon: AppIcon.Action.more,
                accessibilityLabel: "Chat options",
                items: actionItems,
                isCompact: false,
                chromeStyle: chromeStyle
            )
        case .toolbar:
            Menu {
                actionButtons
            } label: {
                Image(appIcon: AppIcon.Action.more)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chat options")
        }
        #endif
    }

    private var actionItems: [SidebarMenuItem] {
        [
            .shareTranscript {
                shareConversation()
            },
            .exportTranscript {
                exportConversation()
            }
        ]
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            shareConversation()
        } label: {
            Label("Share Transcript", systemImage: AppIcon.Action.share.rawValue)
        }
        Button {
            exportConversation()
        } label: {
            Label("Export Transcript", systemImage: AppIcon.Action.download.rawValue)
        }
    }

    private var selectedConversationTitle: String {
        guard let selectedId = viewModel.selectedConversationId,
              let conversation = viewModel.conversations.first(where: { $0.id == selectedId }) else {
            return "Chat"
        }
        return conversation.title
    }

    private var transcriptText: String? {
        let transcript = ConversationCopyFormatter.formattedTranscript(
            title: selectedConversationTitle,
            messages: viewModel.messages,
            assistantName: environment.settingsViewModel.assistantDisplayName
        )
        return transcript.trimmedOrNil
    }

    private func shareConversation() {
        guard let transcriptText else {
            environment.toastCenter.show(message: "Share unavailable")
            return
        }
        SystemSharePresenter.share(text: transcriptText)
    }

    private func exportConversation() {
        guard let transcriptText else {
            environment.toastCenter.show(message: "Export unavailable")
            return
        }
        exportDocument = PlainTextFileDocument(text: transcriptText)
        exportFilename = ConversationCopyFormatter.exportFilename(title: selectedConversationTitle)
        isExporting = true
    }
}

struct ChatHeaderView: View {
    static let actionControlChromeStyle: HeaderActionControlChromeStyle = .glass

    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.workspaceColumn) private var workspaceColumn
    @AppStorage(AppStorageKeys.workspaceExpanded) private var isWorkspaceExpanded: Bool = false
    #if os(iOS)
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) private var isWorkspaceExpandedByRotation: Bool = false
    #endif

    var body: some View {
        headerContent
            .padding(DesignTokens.Spacing.md)
            .frame(height: LayoutMetrics.contentHeaderMinHeight)
            .background(headerBackground)
    }

    private var headerContent: some View {
        ContentHeaderRow(
            iconName: "bubble",
            title: selectedTitle,
            titleLineLimit: 1,
            trailing: {
            HStack(spacing: 12) {
                if showNewChatButton || showCloseButton || showConversationActionsMenu {
                    HeaderActionRow(spacing: DesignTokens.Spacing.xs) {
                        if shouldShowExpandButton {
                            expandButton
                        }
                        if showConversationActionsMenu {
                            ChatConversationActionsMenu(
                                viewModel: viewModel,
                                surface: .header,
                                chromeStyle: Self.actionControlChromeStyle
                            )
                        }
                        if showNewChatButton {
                            HeaderActionButton(
                                systemName: "plus",
                                accessibilityLabel: "New chat",
                                action: {
                                    Task {
                                        await viewModel.startNewConversation()
                                    }
                                },
                                chromeStyle: Self.actionControlChromeStyle
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
                                },
                                chromeStyle: Self.actionControlChromeStyle
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

    private var showConversationActionsMenu: Bool {
        guard viewModel.selectedConversationId != nil else {
            return false
        }
        return !viewModel.isBlankConversation
    }

    private var headerBackground: Color {
        DesignTokens.Colors.background
    }

    private var shouldShowExpandButton: Bool {
        WorkspaceBehaviorPolicy.shouldShowExpandButton(
            workspaceColumn: workspaceColumn,
            isPhoneIdiom: {
                #if os(iOS)
                isPhone
                #else
                false
                #endif
            }()
        )
    }

    private var expandButton: some View {
        HeaderActionButton(
            systemName: expandButtonIconName,
            accessibilityLabel: expandButtonLabel,
            action: expandChatView,
            chromeStyle: Self.actionControlChromeStyle
        )
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

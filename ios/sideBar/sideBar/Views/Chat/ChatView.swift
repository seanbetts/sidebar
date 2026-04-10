import SwiftUI
import sideBarShared
import UniformTypeIdentifiers
import Combine
#if os(iOS)
import UIKit
#endif

// MARK: - ChatView

public struct ChatView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
    }

    public var body: some View {
        ChatDetailView(viewModel: environment.chatViewModel)
            #if !os(macOS)
            .navigationTitle(chatTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCompact {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if !isPhone {
                            Button {
                                Task {
                                    await environment.chatViewModel.startNewConversation()
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("New chat")
                        }
                    }
                }
            }
            #endif
            .onAppear {
                updateAutoRefresh(for: scenePhase)
            }
            .onChange(of: scenePhase) { _, newValue in
                updateAutoRefresh(for: newValue)
            }
            .onDisappear {
                environment.chatViewModel.stopAutoRefresh()
            }
    }

    private func updateAutoRefresh(for scenePhase: ScenePhase) {
        if scenePhase == .active {
            environment.chatViewModel.startAutoRefresh()
        } else {
            environment.chatViewModel.stopAutoRefresh()
        }
    }

    private var chatTitle: String {
        guard isCompact,
              let selectedId = environment.chatViewModel.selectedConversationId,
              let conversation = environment.chatViewModel.conversations.first(where: { $0.id == selectedId }) else {
            return "Chat"
        }
        return conversation.title
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
}

private struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var draftMessage: String = ""
    private let contentMaxWidth: CGFloat = ChatLayout.maxContentWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workspaceColumn) private var workspaceColumn
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var inputMeasuredHeight: CGFloat = 0
    @State private var attachmentsHeight: CGFloat = 0
    @State private var isFileImporterPresented = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if !isCompact {
                    ChatHeaderView(viewModel: viewModel)
                    Divider()
                }
                if environment.settingsViewModel.signedInOnboardingRecoveryState == .providerRecovery {
                    OnboardingAddKeyBanner {
                        UserDefaults.standard.set(
                            "agent",
                            forKey: AppStorageKeys.settingsSelectedSection
                        )
                        UserDefaults.standard.set(
                            "agent",
                            forKey: AppStorageKeys.settingsSelectedTab
                        )
                        environment.commandSelection = .settings
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.sm)
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task {
                        await environment.settingsViewModel.refreshProviderRecoveryStateIfNeeded()
                    }
                } else if environment.settingsViewModel.signedInOnboardingRecoveryState == .soulCalibration,
                          let soulCalibrationState = viewModel.soulCalibrationState {
                    SoulCalibrationPromptView(
                        state: soulCalibrationState,
                        showsIntro: viewModel.shouldShowSoulCalibrationIntro,
                        confirmationText: viewModel.soulCalibrationConfirmationText,
                        errorMessage: viewModel.soulCalibrationErrorMessage,
                        isBusy: viewModel.isSubmittingSoulCalibration,
                        onContinueIntro: {
                            viewModel.acknowledgeSoulCalibrationIntro()
                        },
                        onSubmitPrimaryGoals: { choices in
                            Task {
                                await viewModel.submitSoulCalibrationAnswer(
                                    prompt: .primaryGoal,
                                    .multipleChoice(choices)
                                )
                            }
                        },
                        onSubmitWorkingRelationship: { choice in
                            Task {
                                await viewModel.submitSoulCalibrationAnswer(
                                    prompt: .workingRelationship,
                                    .singleChoice(choice)
                                )
                            }
                        },
                        onSubmitTonePreferences: { choices in
                            Task {
                                await viewModel.submitSoulCalibrationAnswer(
                                    prompt: .tonePreferences,
                                    .multipleChoice(choices)
                                )
                            }
                        },
                        onAcceptName: {
                            Task {
                                await viewModel.acceptSoulCalibrationName()
                            }
                        },
                        onRegenerateName: {
                            Task {
                                await viewModel.regenerateSoulCalibrationName()
                            }
                        }
                    )
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.sm)
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if canShowFeatureDiscovery {
                    StaticFeatureCarousel(
                        onSelectFeature: { feature in
                            Task {
                                await viewModel.startFeatureDiscovery(for: feature)
                            }
                        },
                        onDismiss: {
                            Task {
                                await environment.settingsViewModel.markFeatureDiscoverySeen()
                            }
                        }
                    )
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.sm)
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                if environment.settingsViewModel.signedInOnboardingRecoveryState == .soulCalibration {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.isLoadingMessages {
                    LoadingView(message: "Loading messages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.selectedConversationId == nil {
                    if viewModel.isLoadingConversations && viewModel.conversations.isEmpty {
                        LoadingView(message: "Loading chats…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyView()
                    }
                } else if let errorMessage = viewModel.errorMessage, viewModel.messages.isEmpty {
                    PlaceholderView(
                        title: "Unable to load chat",
                        subtitle: environment.isNetworkAvailable ? errorMessage : "This chat isn't available offline yet.",
                        actionTitle: "Retry"
                    ) {
                        guard let selectedId = viewModel.selectedConversationId else { return }
                        Task { await viewModel.loadConversation(id: selectedId) }
                    }
                } else if !environment.isNetworkAvailable, !viewModel.hasCachedSelectedConversation {
                    PlaceholderView(
                        title: "Unable to load chat",
                        subtitle: "This chat isn't available offline yet.",
                        actionTitle: "Retry"
                    ) {
                        guard let selectedId = viewModel.selectedConversationId else { return }
                        Task { await viewModel.loadConversation(id: selectedId) }
                    }
                } else {
                    ChatMessageListView(
                        viewModel: viewModel,
                        bottomInset: messageListBottomInset,
                        assistantDisplayName: assistantDisplayName
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(spacing: 8) {
                attachmentsContainer
                ChatInputBar(
                    text: $draftMessage,
                    measuredHeight: $inputMeasuredHeight,
                    isEnabled: isComposerEnabled,
                    isSendEnabled: canSendMessages && !viewModel.hasPendingAttachments,
                    isAttachEnabled: canAttachFiles,
                    onSend: handleSend,
                    onAttach: {
                        guard canAttachFiles else { return }
                        isFileImporterPresented = true
                    }
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.md)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event,
                  event.matches(
                    section: .chat,
                    workspacePane: workspaceColumn.workspacePane
                  ) else { return }
            switch event.action {
            case .sendMessage:
                if !viewModel.isStreaming {
                    handleSend()
                }
            case .attachFile:
                guard canAttachFiles else { return }
                isFileImporterPresented = true
            default:
                break
            }
        }
        .onAppear {
            viewModel.syncSoulCalibration(from: environment.settingsViewModel.onboardingState)
        }
        .onChange(of: environment.settingsViewModel.onboardingState) { _, state in
            viewModel.syncSoulCalibration(from: state)
        }
    }

    private var messageListBottomInset: CGFloat {
        max(inputMeasuredHeight, inputBarMinHeight) + attachmentsHeight + 40
    }

    private var inputBarMinHeight: CGFloat {
        #if os(macOS)
        return 84
        #else
        return 46
        #endif
    }

    private var isComposerEnabled: Bool {
        environment.isNetworkAvailable
            && environment.settingsViewModel.signedInOnboardingRecoveryState != .providerRecovery
            && environment.settingsViewModel.signedInOnboardingRecoveryState != .soulCalibration
    }

    private var canSendMessages: Bool {
        isComposerEnabled && !viewModel.isStreaming
    }

    private var canAttachFiles: Bool {
        isComposerEnabled && !viewModel.isStreaming
    }

    private var assistantDisplayName: String {
        environment.settingsViewModel.assistantDisplayName
    }

    private var canShowFeatureDiscovery: Bool {
        environment.settingsViewModel.signedInOnboardingRecoveryState == .featureDiscovery
            && viewModel.canShowFeatureDiscovery
    }

    private func handleSend() {
        let message = draftMessage.trimmed
        guard !message.isEmpty, canSendMessages else {
            return
        }
        draftMessage = ""
        Task {
            await viewModel.sendMessage(text: message)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            viewModel.addAttachments(urls: urls)
        case .failure:
            environment.toastCenter.show(message: "Failed to attach file")
        }
    }

    private var attachmentsContainer: some View {
        VStack(spacing: 8) {
            if !viewModel.pendingAttachments.isEmpty {
                PendingAttachmentsView(
                    attachments: viewModel.pendingAttachments,
                    onRetry: { viewModel.retryAttachment(id: $0) },
                    onDelete: { viewModel.deleteAttachment(id: $0) },
                    onCancel: { viewModel.cancelAttachment(id: $0) }
                )
            }
            if !viewModel.readyAttachments.isEmpty {
                ReadyAttachmentsView(
                    attachments: viewModel.readyAttachments,
                    onRemove: { viewModel.removeReadyAttachment(id: $0) }
                )
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: AttachmentHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(AttachmentHeightPreferenceKey.self) { height in
            attachmentsHeight = height
        }
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}

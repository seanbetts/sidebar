import SwiftUI
import sideBarShared

#if os(macOS)
extension UserSettingsView {
    var macUserSettingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                if shouldShowQueuedChangesRecovery {
                    SettingsMacPanelCard {
                        SettingsMacSectionIntro(
                            title: "Sync errors",
                            message: "Review failed queued changes and retry them when you're ready."
                        )
                        SettingsMacStatusBanner(message: queuedChangeStatusText, tone: .error)
                        SettingsMacActionSection(
                            title: "Queued changes",
                            message: "Open the queued changes view to inspect failures and retry the write queue."
                        ) {
                            Button("Review failed changes") {
                                isQueuedChangesPresented = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                SettingsMacPanelCard {
                    SettingsMacSectionIntro(
                        title: "Communication style",
                        message: "Set the tone and level of directness your assistant should use when it responds."
                    )
                    SettingsMacPlainTextEditor(text: $communicationStyle, minHeight: 160)
                        .padding(DesignTokens.Spacing.sm)
                        .sidebarTextEntrySurface()
                }

                SettingsMacPanelCard {
                    SettingsMacSectionIntro(
                        title: "Working relationship",
                        message: "Describe how you want sideBar to collaborate with you during planning and execution."
                    )
                    SettingsMacPlainTextEditor(text: $workingRelationship, minHeight: 160)
                        .padding(DesignTokens.Spacing.sm)
                        .sidebarTextEntrySurface()
                }

            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.settingsBackground)
        .sheet(isPresented: $isQueuedChangesPresented) {
            MacModalShell(type: queuedChangesPanelType()) {
                NavigationStack {
                    QueuedChangesView()
                }
            }
            .phoneSheetGrabBarVisible()
        }
        .onAppear {
            syncDraftsFromSettings(viewModel.settings)
        }
        .onChange(of: systemAutosaveSignature) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: settingsSignature) { _, _ in
            syncDraftsFromSettings(viewModel.settings)
        }
        .onDisappear {
            flushPendingSystemAutosave()
        }
        .overlay {
            if viewModel.isLoading && viewModel.settings == nil {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
    }
}

extension AgentSettingsView {
    var macAgentSettingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                SettingsMacPanelCard {
                    SettingsMacSectionIntro(
                        title: "AI provider",
                        message: "Choose the primary model provider sideBar should use for assistant responses."
                    )
                    FormField("Provider") {
                        SidebarSelectionMenu(
                            selection: $selectedPrimaryProvider,
                            options: viewModel.supportedPrimaryProviders,
                            accessibilityLabel: "Provider",
                            title: { $0.displayName }
                        )
                    }

                    if selectedProviderHasKey {
                        FormField("API key") {
                            HStack(spacing: DesignTokens.Spacing.sm) {
                                Text(maskedProviderKeyText)
                                    .appFont(.body)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Button {
                                    Task {
                                        await viewModel.deletePrimaryProviderKey(provider: selectedPrimaryProvider)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isSavingPrimaryProvider)
                                .accessibilityLabel("Clear API Key")
                            }
                        }
                    } else {
                        FormField("API key") {
                            SecureField("Enter \(selectedPrimaryProvider.displayName) API key", text: $providerKeyInput)
                                .sidebarTextEntryField()
                                .frame(maxWidth: 320)
                                .disabled(viewModel.isSavingPrimaryProvider)
                                .onSubmit {
                                    Task {
                                        let success = await viewModel.savePrimaryProviderKey(
                                            provider: selectedPrimaryProvider,
                                            apiKey: providerKeyInput
                                        )
                                        if success {
                                            Haptics.selection()
                                            providerKeyInput = ""
                                        }
                                    }
                                }
                        }
                    }
                }

                macReadOnlyCard(
                    title: Self.assistantSectionTitle("Name", assistantDisplayName: assistantDisplayName),
                    message: "Your assistant's name."
                ) {
                    Text(resolvedText(viewModel.settings?.assistantIdentity?.name))
                }
                macReadOnlyCard(
                    title: Self.assistantSectionTitle("Tone", assistantDisplayName: assistantDisplayName),
                    message: "How \(assistantDisplayName) should sound and respond."
                ) {
                    Text(resolvedText(viewModel.settings?.assistantIdentity?.tone))
                }
                macReadOnlyCard(
                    title: Self.assistantSectionTitle("Values", assistantDisplayName: assistantDisplayName),
                    message: "Core principles \(assistantDisplayName) prioritizes."
                ) {
                    Text(resolvedText(viewModel.settings?.assistantIdentity?.values))
                }
                macReadOnlyCard(
                    title: Self.assistantSectionTitle("Boundaries", assistantDisplayName: assistantDisplayName),
                    message: "Limits \(assistantDisplayName) should not cross."
                ) {
                    Text(resolvedText(viewModel.settings?.assistantIdentity?.boundaries))
                }

                if let identityMeta = viewModel.settings?.assistantIdentityMeta {
                    macReadOnlyCard(
                        title: Self.assistantSectionTitle("Identity Meta", assistantDisplayName: assistantDisplayName),
                        message: "History of identity updates \(assistantDisplayName) has made."
                    ) {
                        identityMetaLines(identityMeta)
                    }
                }

                macReadOnlyCard(
                    title: Self.assistantSectionTitle("Purpose", assistantDisplayName: assistantDisplayName),
                    message: "\(assistantPossessiveDisplayName) long-term mission and intent."
                ) {
                    Text(resolvedText(viewModel.settings?.assistantSoul?.purpose))
                }
                macReadOnlyCard(
                    title: Self.assistantSectionTitle("Operating Principles", assistantDisplayName: assistantDisplayName),
                    message: "Standing rules that guide \(assistantPossessiveDisplayName) day-to-day behavior."
                ) {
                    Text(resolvedText(viewModel.settings?.assistantSoul?.operatingPrinciples))
                }
                macReadOnlyCard(
                    title: Self.assistantSectionTitle("Adaptation Policy", assistantDisplayName: assistantDisplayName),
                    message: "How \(assistantDisplayName) should adapt while staying aligned."
                ) {
                    Text(resolvedText(viewModel.settings?.assistantSoul?.adaptationPolicy))
                }
                macReadOnlyCard(
                    title: Self.assistantSectionTitle("Success Signals", assistantDisplayName: assistantDisplayName),
                    message: "How \(assistantDisplayName) measures good outcomes and alignment."
                ) {
                    Text(resolvedText(viewModel.settings?.assistantSoul?.successSignals))
                }

                if let soulMeta = viewModel.settings?.assistantSoulMeta {
                    macReadOnlyCard(
                        title: Self.assistantSectionTitle("Soul Meta", assistantDisplayName: assistantDisplayName),
                        message: "History of soul updates \(assistantDisplayName) has made."
                    ) {
                        identityMetaLines(soulMeta)
                    }
                }

                SettingsMacStatusBanner(
                    message: "Managed by \(assistantDisplayName). User edits are disabled for these fields.",
                    tone: .info
                )
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.settingsBackground)
        .overlay {
            if viewModel.isLoading && viewModel.settings == nil {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
        .onAppear {
            syncSelectedProvider(from: viewModel.settings)
        }
        .onChange(of: primaryProviderSignature) { _, _ in
            syncSelectedProvider(from: viewModel.settings)
        }
        .onChange(of: selectedPrimaryProvider) { previous, next in
            if previous == next {
                return
            }
            Task {
                await viewModel.savePrimaryProvider(next)
            }
        }
    }

    @ViewBuilder
    func macReadOnlyCard(
        title: String,
        message: String,
        @ViewBuilder value: () -> some View
    ) -> some View {
        SettingsMacPanelCard {
            SettingsMacSectionIntro(title: title, message: message)
            value()
                .appFont(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    func identityMetaLines(_ meta: AgentFieldMeta) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Updated: \(meta.updatedAt)")
            Text("Version: \(meta.version)")
            if let reason = meta.reason, !reason.isEmpty {
                Text("Reason: \(reason)")
            }
        }
        .appFont(.body)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

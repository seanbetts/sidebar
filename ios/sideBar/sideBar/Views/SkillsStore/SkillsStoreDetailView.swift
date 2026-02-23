import SwiftUI
import sideBarShared

public struct SkillsStoreView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var hasLoaded = false
    @State private var selectedCategory: String?
    @State private var searchQuery: String = ""
    @FocusState private var isSearchFocused: Bool

    @State private var installInFlight: Set<String> = []
    @State private var installChecksInFlight: Set<String> = []
    @State private var uninstallInFlight: Set<String> = []
    @State private var installErrors: [String: String] = [:]

    @State private var selectedStoreSkill: SkillItem?
    @State private var storeInstallPrompt: StoreInstallPrompt?
    @State private var storeUninstallPrompt: StoreUninstallPrompt?
    @State private var providerKeyDrafts: [String: String] = [:]
    @State private var storeInstallPromptError: String?
    @State private var isSubmittingStoreInstallPrompt = false

    public init() {
    }

    public var body: some View {
        Group {
            if viewModel.isLoadingSkills && storeSkills.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            } else if let error = viewModel.skillsError, storeSkills.isEmpty {
                PlaceholderView(
                    title: "Unable to load Skills Store",
                    subtitle: error,
                    iconName: "exclamationmark.triangle"
                )
            } else {
                skillsStoreContent
            }
        }
        .navigationTitle("Skills Store")
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task {
                    if viewModel.settings == nil {
                        await viewModel.load()
                    }
                    await viewModel.loadSkills()
                }
            }
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event, event.section == .skillsStore else { return }
            if event.action == .focusSearch {
                isSearchFocused = true
            }
        }
        .sheet(item: $storeInstallPrompt, onDismiss: clearStoreInstallPromptState) { prompt in
            storeInstallSheet(prompt)
        }
        .sheet(item: $selectedStoreSkill) { skill in
            StoreSkillDetailSheet(
                viewModel: viewModel,
                skill: skill,
                isStoreActionBusy: isStoreActionBusy(skill.id),
                isInstalled: isInstalled(skill),
                installError: installErrors[skill.id],
                onInstallTap: {
                    Task {
                        await beginStoreInstall(for: skill)
                    }
                },
                onConfirmUninstall: {
                    _ = await performStoreUninstall(skillId: skill.id)
                }
            )
        }
        .alert(
            "Uninstall skill?",
            isPresented: isStoreUninstallPromptPresented,
            presenting: storeUninstallPrompt
        ) { prompt in
            Button("Uninstall", role: .destructive) {
                Task {
                    let succeeded = await performStoreUninstall(skillId: prompt.skill.id)
                    if succeeded {
                        storeUninstallPrompt = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                storeUninstallPrompt = nil
            }
        } message: { prompt in
            Text("This will uninstall \(viewModel.displayName(for: prompt.skill)).")
        }
    }

    private var viewModel: SettingsViewModel {
        environment.settingsViewModel
    }

    private var skillsStoreContent: some View {
        VStack(spacing: 0) {
            if !isCompact {
                headerBar
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    if isCompact {
                        compactSearchField
                    }
                    categoryFilter
                    content
                }
                .padding(DesignTokens.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var headerBar: some View {
        ContentHeaderRow(
            iconName: "text.and.command.macwindow",
            title: "Skills Store",
            titleFont: .subheadline.weight(.semibold),
            titleLineLimit: 1,
            trailing: {
                SearchField(
                    text: $searchQuery,
                    placeholder: "Search store skills",
                    isFocused: $isSearchFocused
                )
                .frame(width: 280)
            }
        )
        .padding(DesignTokens.Spacing.md)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    private var compactSearchField: some View {
        SearchField(
            text: $searchQuery,
            placeholder: "Search store skills",
            isFocused: $isSearchFocused
        )
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                SkillsStoreFilterChip(
                    title: "All",
                    iconName: SkillsStoreCategoryIcon.iconName(for: "all"),
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                ForEach(storeCategories, id: \.self) { category in
                    SkillsStoreFilterChip(
                        title: category,
                        iconName: SkillsStoreCategoryIcon.iconName(for: category),
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        if filteredSkills.isEmpty {
            PlaceholderView(
                title: "No store skills found",
                subtitle: searchQuery.trimmed.isEmpty ? "Try another category." : "Try a different search.",
                iconName: "magnifyingglass"
            )
        } else {
            LazyVGrid(columns: skillGridColumns, spacing: DesignTokens.Spacing.md) {
                ForEach(filteredSkills, id: \.id) { skill in
                    skillCard(skill)
                }
            }
        }
    }

    private func skillCard(_ skill: SkillItem) -> some View {
        let busy = isStoreActionBusy(skill.id)
        let installed = isInstalled(skill)

        return SkillsStoreCard(
            skillIconName: SkillIconResolver.iconName(for: skill),
            typeTitle: formattedSkillType(skill.category),
            displayName: viewModel.displayName(for: skill),
            displayDescription: viewModel.displayDescription(for: skill),
            installError: installErrors[skill.id],
            isBusy: busy,
            isInstalled: installed,
            onInstall: {
                Task {
                    await beginStoreInstall(for: skill)
                }
            },
            onCardTap: {
                selectedStoreSkill = skill
            },
            onInstalledTap: {
                storeUninstallPrompt = StoreUninstallPrompt(skill: skill)
            }
        )
    }

    private var storeSkills: [SkillItem] {
        SkillsStoreLogic.storeSkills(from: viewModel.skills)
    }

    private var storeCategories: [String] {
        SkillsStoreLogic.categories(from: storeSkills)
    }

    private var filteredSkills: [SkillItem] {
        SkillsStoreLogic.filteredStoreSkills(
            storeSkills,
            selectedCategory: selectedCategory,
            searchQuery: searchQuery
        ) { skill in
            [
                viewModel.displayName(for: skill),
                viewModel.displayDescription(for: skill),
                skill.category
            ].joined(separator: " ")
        }
    }

    private func beginStoreInstall(for skill: SkillItem) async {
        guard !isStoreActionBusy(skill.id) else { return }
        installErrors[skill.id] = nil
        let requiredProviders = SkillsStoreLogic.requiredProviders(for: skill)
        guard !requiredProviders.isEmpty else {
            _ = await performStoreInstall(skillId: skill.id, providerKeys: [])
            return
        }

        installChecksInFlight.insert(skill.id)
        defer { installChecksInFlight.remove(skill.id) }

        do {
            var missingProviders: [String] = []
            for provider in requiredProviders {
                let hasKey = try await viewModel.providerHasKey(provider: provider)
                if !hasKey {
                    missingProviders.append(provider)
                }
            }

            if missingProviders.isEmpty {
                _ = await performStoreInstall(skillId: skill.id, providerKeys: [])
                return
            }

            storeInstallPrompt = StoreInstallPrompt(skill: skill, missingProviders: missingProviders)
            providerKeyDrafts = Dictionary(uniqueKeysWithValues: missingProviders.map { ($0, "") })
            storeInstallPromptError = nil
        } catch {
            installErrors[skill.id] = ErrorMapping.message(for: error)
        }
    }

    private func submitStoreInstallPrompt(_ prompt: StoreInstallPrompt) async {
        storeInstallPromptError = nil
        let providerKeys = prompt.missingProviders.compactMap { provider -> StoreSkillProviderKeyInput? in
            let key = providerKeyDrafts[provider]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else { return nil }
            return StoreSkillProviderKeyInput(provider: provider, apiKey: key)
        }
        guard providerKeys.count == prompt.missingProviders.count else {
            storeInstallPromptError = "All required provider keys must be entered."
            return
        }

        isSubmittingStoreInstallPrompt = true
        defer { isSubmittingStoreInstallPrompt = false }

        let succeeded = await performStoreInstall(skillId: prompt.skill.id, providerKeys: providerKeys)
        if succeeded {
            storeInstallPrompt = nil
            clearStoreInstallPromptState()
        } else {
            storeInstallPromptError = installErrors[prompt.skill.id] ?? "Install failed."
        }
    }

    private func performStoreInstall(
        skillId: String,
        providerKeys: [StoreSkillProviderKeyInput]
    ) async -> Bool {
        guard !installInFlight.contains(skillId) else { return false }
        installInFlight.insert(skillId)
        defer { installInFlight.remove(skillId) }

        let succeeded = await viewModel.installStoreSkill(id: skillId, providerKeys: providerKeys)
        if succeeded {
            installErrors[skillId] = nil
            return true
        }

        let message = viewModel.skillsError?.trimmingCharacters(in: .whitespacesAndNewlines)
        installErrors[skillId] = (message?.isEmpty == false) ? message : "Install failed."
        return false
    }

    private func performStoreUninstall(skillId: String) async -> Bool {
        guard !uninstallInFlight.contains(skillId) else { return false }
        uninstallInFlight.insert(skillId)
        defer { uninstallInFlight.remove(skillId) }

        installErrors[skillId] = nil
        let succeeded = await viewModel.uninstallStoreSkill(id: skillId)
        if succeeded {
            installErrors[skillId] = nil
            return true
        }

        let message = viewModel.skillsError?.trimmingCharacters(in: .whitespacesAndNewlines)
        installErrors[skillId] = (message?.isEmpty == false) ? message : "Uninstall failed."
        return false
    }

    private func providerKeyBinding(for provider: String) -> Binding<String> {
        Binding(
            get: { providerKeyDrafts[provider] ?? "" },
            set: { providerKeyDrafts[provider] = $0 }
        )
    }

    private func clearStoreInstallPromptState() {
        providerKeyDrafts = [:]
        storeInstallPromptError = nil
        isSubmittingStoreInstallPrompt = false
    }

    private func isStoreActionBusy(_ skillId: String) -> Bool {
        SkillsStoreLogic.isStoreActionBusy(
            skillId: skillId,
            installInFlight: installInFlight,
            installChecksInFlight: installChecksInFlight,
            uninstallInFlight: uninstallInFlight
        )
    }

    private func isInstalled(_ skill: SkillItem) -> Bool {
        SkillsStoreLogic.isInstalled(
            skillId: skill.id,
            installedStoreSkillIds: Set(viewModel.settings?.installedStoreSkills ?? [])
        )
    }

    private var skillGridColumns: [GridItem] {
        if isCompact {
            return [
                GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: DesignTokens.Spacing.md)
            ]
        }
        return [
            GridItem(
                .adaptive(minimum: 320, maximum: 420),
                spacing: DesignTokens.Spacing.md
            )
        ]
    }

    private func formattedSkillType(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var isStoreUninstallPromptPresented: Binding<Bool> {
        Binding(
            get: { storeUninstallPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    storeUninstallPrompt = nil
                }
            }
        )
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}

private extension SkillsStoreView {
    func storeInstallSheet(_ prompt: StoreInstallPrompt) -> some View {
        NavigationStack {
            Form {
                Section {
                    Text(viewModel.displayDescription(for: prompt.skill))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(viewModel.displayName(for: prompt.skill))
                }

                Section("Required Provider Keys") {
                    ForEach(prompt.missingProviders, id: \.self) { provider in
                        SecureField(
                            "\(SkillsStoreLogic.providerDisplayName(provider)) API key",
                            text: providerKeyBinding(for: provider)
                        )
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        #endif
                    }
                    if let storeInstallPromptError, !storeInstallPromptError.isEmpty {
                        Text(storeInstallPromptError)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Colors.error)
                    }
                }

                Section {
                    Button {
                        Task {
                            await submitStoreInstallPrompt(prompt)
                        }
                    } label: {
                        if isSubmittingStoreInstallPrompt {
                            ProgressView()
                        } else {
                            Text("Install Skill")
                        }
                    }
                    .disabled(isSubmittingStoreInstallPrompt)
                } footer: {
                    Text("Keys are saved for future installs and reused automatically.")
                }
            }
            .navigationTitle("Install Skill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        storeInstallPrompt = nil
                    }
                }
            }
        }
        .phoneSheetGrabBarVisible()
    }
}

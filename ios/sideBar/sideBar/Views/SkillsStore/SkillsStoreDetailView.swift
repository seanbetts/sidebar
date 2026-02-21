import SwiftUI
import sideBarShared

public struct SkillsStoreView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var hasLoaded = false
    @State private var selectedCategory: String?
    @State private var searchQuery: String = ""
    @FocusState private var isSearchFocused: Bool

    @State private var installInFlight: Set<String> = []
    @State private var installChecksInFlight: Set<String> = []
    @State private var installErrors: [String: String] = [:]
    @State private var storeInstallPrompt: StoreInstallPrompt?
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
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        workspaceHeader
                        categoryFilter
                        content
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(DesignTokens.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
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

    private var viewModel: SettingsViewModel {
        environment.settingsViewModel
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Discover skills")
                .font(DesignTokens.Typography.title2Semibold)
            Text("Install what you need. Skill enablement is managed in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SearchField(
                text: $searchQuery,
                placeholder: "Search store skills",
                isFocused: $isSearchFocused
            )
        }
    }

    @ViewBuilder
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                filterChip(title: "All", category: nil)
                ForEach(storeCategories, id: \.self) { category in
                    filterChip(title: category, category: category)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(title: String, category: String?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isSelected
                            ? Color.accentColor.opacity(0.18)
                            : DesignTokens.Colors.surface
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
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
            LazyVStack(spacing: DesignTokens.Spacing.md) {
                ForEach(filteredSkills, id: \.id) { skill in
                    skillCard(skill)
                }
            }
        }
    }

    private func skillCard(_ skill: SkillItem) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Image(systemName: SkillsStoreLogic.iconName(for: skill))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.displayName(for: skill))
                        .font(DesignTokens.Typography.subheadlineSemibold)
                    Text(viewModel.displayDescription(for: skill))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(skill.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                installButton(skill)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(SkillsStoreLogic.requirementLines(for: skill).enumerated()), id: \.offset) { _, line in
                    Label(line, systemImage: "key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let installError = installErrors[skill.id], !installError.isEmpty {
                Text(installError)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func installButton(_ skill: SkillItem) -> some View {
        let busy = isStoreInstallBusy(skill.id)
        let installed = isInstalled(skill)

        Button {
            Task {
                await beginStoreInstall(for: skill)
            }
        } label: {
            if busy {
                ProgressView()
                    .controlSize(.small)
            } else if installed {
                Text("Installed")
            } else {
                Text("Install")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(
            installed
            || busy
            || viewModel.isSavingSkills
            || viewModel.settings == nil
            || !skill.installable
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
        guard !isStoreInstallBusy(skill.id) else { return }
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

    private func isStoreInstallBusy(_ skillId: String) -> Bool {
        installInFlight.contains(skillId) || installChecksInFlight.contains(skillId)
    }

    private func isInstalled(_ skill: SkillItem) -> Bool {
        viewModel.settings?.installedStoreSkills.contains(skill.id) ?? false
    }
}

private struct StoreInstallPrompt: Identifiable {
    let skill: SkillItem
    let missingProviders: [String]

    var id: String { skill.id }
}

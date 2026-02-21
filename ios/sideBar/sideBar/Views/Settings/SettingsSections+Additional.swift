import SwiftUI
import sideBarShared

// MARK: - Additional Settings Sections

struct SkillsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedTier: SkillsTierFilter = .standard
    @State private var installInFlight: Set<String> = []

    var body: some View {
        Form {
            Section {
                Picker("Skill Type", selection: $selectedTier) {
                    ForEach(SkillsTierFilter.allCases) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Enable all", isOn: Binding(
                    get: { allSkillsEnabled },
                    set: { isEnabled in
                        Task { await viewModel.setAllSkillsEnabled(isEnabled, scopeSkillIds: enableAllScopeSkillIds) }
                    }
                ))
                .disabled(
                    viewModel.isSavingSkills ||
                    viewModel.isLoadingSkills ||
                    viewModel.settings == nil ||
                    !hasToggleableSkills
                )
            }
            if let error = viewModel.skillsError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }
            if groupedSkills.isEmpty && !viewModel.isLoadingSkills {
                Section {
                    Text("No skills available.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groupedSkills, id: \.0) { category, skills in
                    Section(category) {
                        ForEach(skills, id: \.id) { skill in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: Binding(
                                    get: { isSkillEnabled(skill.id) },
                                    set: { isEnabled in
                                        Task { await viewModel.setSkillEnabled(id: skill.id, enabled: isEnabled) }
                                    }
                                )) {
                                    skillLabel(skill)
                                }
                                .disabled(
                                    viewModel.isSavingSkills ||
                                    viewModel.settings == nil ||
                                    !skill.userToggleable ||
                                    (selectedTier == .store && !isStoreSkillInstalled(skill))
                                )

                                if selectedTier == .store {
                                    storeRequirementLines(skill)
                                    storeInstallButton(skill)
                                }
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .overlay {
            if viewModel.isLoadingSkills && viewModel.skills.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
    }

    private enum SkillsTierFilter: String, CaseIterable, Identifiable {
        case standard
        case store
        case required

        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard:
                return "Standard"
            case .store:
                return "Store"
            case .required:
                return "Required"
            }
        }
    }

    @ViewBuilder
    private func skillLabel(_ skill: SkillItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.displayName(for: skill))
                    .font(DesignTokens.Typography.subheadlineSemibold)

                if selectedTier == .store && isStoreSkillInstalled(skill) {
                    Text("Installed")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(DesignTokens.Colors.success.opacity(0.18)))
                        .foregroundStyle(DesignTokens.Colors.success)
                }

                if !skill.userToggleable && skill.showRequiredBadge {
                    Text("Required")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }

            Text(viewModel.displayDescription(for: skill))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func storeRequirementLines(_ skill: SkillItem) -> some View {
        ForEach(Array(requirementLines(for: skill).enumerated()), id: \.offset) { _, line in
            Label(line, systemImage: "key")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func storeInstallButton(_ skill: SkillItem) -> some View {
        if skill.installable && !isStoreSkillInstalled(skill) {
            Button {
                Task {
                    await installStoreSkill(skill.id)
                }
            } label: {
                if installInFlight.contains(skill.id) {
                    ProgressView()
                } else {
                    Text("Install")
                }
            }
            .disabled(
                installInFlight.contains(skill.id) ||
                viewModel.isSavingSkills ||
                viewModel.settings == nil
            )
        }
    }

    private func installStoreSkill(_ skillId: String) async {
        guard !installInFlight.contains(skillId) else { return }
        installInFlight.insert(skillId)
        defer { installInFlight.remove(skillId) }
        await viewModel.installStoreSkill(id: skillId)
    }

    private func requirementLines(for skill: SkillItem) -> [String] {
        if skill.credentialRequirements.isEmpty {
            return ["No API key required"]
        }
        return skill.credentialRequirements.map { requirement in
            let provider = providerDisplayName(requirement.provider)
            if requirement.required {
                return "Requires \(provider) API key"
            }
            if let mode = requirement.mode, !mode.isEmpty {
                return "Optional \(provider) API key (\(mode.replacingOccurrences(of: "_", with: " ")))"
            }
            return "Optional \(provider) API key"
        }
    }

    private func providerDisplayName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "openai":
            return "OpenAI"
        case "anthropic":
            return "Anthropic"
        case "google":
            return "Google"
        default:
            return raw.capitalized
        }
    }

    private var filteredSkills: [SkillItem] {
        viewModel.skills.filter { skill in
            switch selectedTier {
            case .standard:
                return skill.tier == .standard
            case .store:
                return skill.tier == .store && skill.status != "hidden"
            case .required:
                return skill.tier == .required
            }
        }
    }

    private var groupedSkills: [(String, [SkillItem])] {
        let grouped = Dictionary(grouping: filteredSkills) { $0.category }
        return grouped.keys.sorted().map { key in
            (key, grouped[key]?.sorted { $0.name < $1.name } ?? [])
        }
    }

    private var enableAllScopeSkillIds: Set<String> {
        Set(
            filteredSkills
                .filter { $0.userToggleable }
                .filter { selectedTier != .store || isStoreSkillInstalled($0) }
                .map(\.id)
        )
    }

    private var allSkillsEnabled: Bool {
        let enabled = Set(viewModel.settings?.enabledSkills ?? [])
        let all = enableAllScopeSkillIds
        return !all.isEmpty && enabled.isSuperset(of: all)
    }

    private var hasToggleableSkills: Bool {
        !enableAllScopeSkillIds.isEmpty
    }

    private func isSkillEnabled(_ id: String) -> Bool {
        viewModel.settings?.enabledSkills.contains(id) ?? false
    }

    private func isStoreSkillInstalled(_ skill: SkillItem) -> Bool {
        guard selectedTier == .store else { return true }
        guard skill.installable else { return true }
        return viewModel.settings?.installedStoreSkills.contains(skill.id) ?? false
    }
}

struct MemoriesSettingsView: View {
    @ObservedObject var viewModel: MemoriesViewModel

    var body: some View {
        #if os(macOS)
        Form {
            Section("Memories") {
                Text("Manage and view memories in the main workspace.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        #else
        MemoriesSettingsDetailView(viewModel: viewModel)
        #endif
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var copied = false

    var body: some View {
        Form {
            Section("Shortcuts") {
                Text("Use this token in Apple Shortcuts to authorize quick capture.")
                    .foregroundStyle(.secondary)
                TextField("Token", text: .constant(viewModel.shortcutsToken))
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    Button(copied ? "Copied" : "Copy") {
                        copyToken()
                    }
                    .disabled(viewModel.shortcutsToken.isEmpty)

                    Button(viewModel.isRotatingShortcuts ? "Regenerating..." : "Regenerate") {
                        Task { await viewModel.rotateShortcutsToken() }
                    }
                    .disabled(viewModel.isRotatingShortcuts || viewModel.isLoadingShortcuts)
                }
                if let error = viewModel.shortcutsError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .overlay {
            if viewModel.isLoadingShortcuts && viewModel.shortcutsToken.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
    }

    private func copyToken() {
        guard !viewModel.shortcutsToken.isEmpty else { return }
        let token = viewModel.shortcutsToken
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)
        #else
        let pasteboard = UIPasteboard.general
        pasteboard.string = token
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == token {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == token {
                pasteboard.string = ""
            }
            #endif
        }
    }
}

struct TasksSettingsView: View {
    var body: some View {
        Form {
            Section("Tasks") {
                Text("Tasks sync uses the built-in sideBar task system.")
                    .foregroundStyle(.secondary)
                Text("Set up your tasks in sideBar to see them here.")
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

struct APISettingsView: View {
    let settings: UserSettings?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section("API") {
                if let userId = settings?.userId {
                    LabeledContent("User ID", value: userId)
                }
                Text("API settings are managed by your server configuration.")
                    .foregroundStyle(.secondary)
            }
#if DEBUG
            Section("Debug") {
                HStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                        Text("AppLogo (system)")
                            .font(.caption)
                    }
                    VStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .environment(\.colorScheme, .dark)
                        Text("AppLogo (forced dark)")
                            .font(.caption)
                    }
                }
                Text("Color scheme: \(colorScheme == .dark ? "dark" : "light")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
#endif
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

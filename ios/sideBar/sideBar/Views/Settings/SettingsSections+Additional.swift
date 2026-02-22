import Foundation
import SwiftUI
import sideBarShared

// MARK: - Additional Settings Sections

struct SkillsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedTier: SkillsTierFilter = .standard
    @State private var selectedStoreSkill: SkillItem?

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
                        Task {
                            await viewModel.setAllSkillsEnabled(
                                isEnabled,
                                scopeSkillIds: enableAllScopeSkillIds
                            )
                        }
                    }
                ))
                .disabled(
                    viewModel.isSavingSkills
                    || viewModel.isLoadingSkills
                    || viewModel.settings == nil
                    || !hasToggleableSkills
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
                            if selectedTier == .store {
                                storeSkillRow(skill)
                            } else {
                                skillToggleRow(skill)
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .sheet(item: $selectedStoreSkill) { skill in
            NavigationStack {
                StoreSkillConfigView(viewModel: viewModel, skill: skill)
                    .navigationTitle(viewModel.displayName(for: skill))
            }
            .settingsSheetGrabBarVisible()
        }
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
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: SkillsStoreLogic.iconName(for: skill))
                .font(.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.displayName(for: skill))
                    .font(DesignTokens.Typography.subheadlineSemibold)

                Text(viewModel.displayDescription(for: skill))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func skillToggleRow(_ skill: SkillItem) -> some View {
        Toggle(isOn: Binding(
            get: { isSkillEnabled(skill.id) },
            set: { isEnabled in
                Task { await viewModel.setSkillEnabled(id: skill.id, enabled: isEnabled) }
            }
        )) {
            skillLabel(skill)
        }
        .disabled(
            viewModel.isSavingSkills
            || viewModel.settings == nil
            || !skill.userToggleable
        )
    }

    private func storeSkillRow(_ skill: SkillItem) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Button {
                selectedStoreSkill = skill
            } label: {
                skillLabel(skill)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { isSkillEnabled(skill.id) },
                set: { isEnabled in
                    Task { await viewModel.setSkillEnabled(id: skill.id, enabled: isEnabled) }
                }
            ))
            .labelsHidden()
            .disabled(
                viewModel.isSavingSkills
                || viewModel.settings == nil
                || !skill.userToggleable
            )
        }
    }

    private var filteredSkills: [SkillItem] {
        viewModel.skills.filter { skill in
            switch selectedTier {
            case .standard:
                return skill.tier == .standard
            case .store:
                return skill.tier == .store
                    && skill.status != "hidden"
                    && isStoreSkillInstalled(skill)
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
        viewModel.settings?.installedStoreSkills.contains(skill.id) ?? false
    }
}

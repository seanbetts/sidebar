import SwiftUI
import sideBarShared

// MARK: - Additional Settings Sections

struct SkillsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable all", isOn: Binding(
                    get: { allSkillsEnabled },
                    set: { isEnabled in
                        Task { await viewModel.setAllSkillsEnabled(isEnabled) }
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
            if viewModel.isSavingSkills {
                Section {
                    HStack(spacing: 8) {
                        LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                        Text("Saving skills…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                            Toggle(isOn: Binding(
                                get: { isSkillEnabled(skill.id) },
                                set: { isEnabled in
                                    Task { await viewModel.setSkillEnabled(id: skill.id, enabled: isEnabled) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.displayName(for: skill))
                                        .font(DesignTokens.Typography.subheadlineSemibold)
                                    Text(skill.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !skill.userToggleable {
                                        Text("Required")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                    }
                                }
                            }
                            .disabled(
                                viewModel.isSavingSkills ||
                                viewModel.settings == nil ||
                                !skill.userToggleable
                            )
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

    private var groupedSkills: [(String, [SkillItem])] {
        let grouped = Dictionary(grouping: viewModel.skills) { $0.category }
        return grouped.keys.sorted().map { key in
            (key, grouped[key]?.sorted { $0.name < $1.name } ?? [])
        }
    }

    private var allSkillsEnabled: Bool {
        let enabled = Set(viewModel.settings?.enabledSkills ?? [])
        let all = Set(viewModel.skills.filter(\.userToggleable).map(\.id))
        return !all.isEmpty && enabled.isSuperset(of: all)
    }

    private var hasToggleableSkills: Bool {
        viewModel.skills.contains(where: \.userToggleable)
    }

    private func isSkillEnabled(_ id: String) -> Bool {
        viewModel.settings?.enabledSkills.contains(id) ?? false
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

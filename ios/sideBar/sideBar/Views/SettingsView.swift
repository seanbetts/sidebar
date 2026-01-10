import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        #if os(macOS)
        SettingsSplitView(viewModel: environment.settingsViewModel)
        #else
        SettingsTabsView(viewModel: environment.settingsViewModel)
        #endif
    }
}

#if os(macOS)
private enum SettingsSection: String, CaseIterable, Identifiable {
    case profile
    case system
    case skills
    case shortcuts
    case things
    case memories
    case api

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile:
            return "Profile"
        case .system:
            return "System"
        case .skills:
            return "Skills"
        case .memories:
            return "Memories"
        case .shortcuts:
            return "Shortcuts"
        case .things:
            return "Things"
        case .api:
            return "API"
        }
    }

    var systemImage: String {
        switch self {
        case .profile:
            return "person.crop.circle"
        case .system:
            return "slider.horizontal.3"
        case .skills:
            return "sparkles"
        case .memories:
            return "brain"
        case .shortcuts:
            return "bolt.horizontal.circle"
        case .things:
            return "checkmark.circle"
        case .api:
            return "link"
        }
    }
}

private struct SettingsSplitView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selection: SettingsSection? = .profile
    @State private var hasLoaded = false

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
        } detail: {
            settingsDetailView(for: selection ?? .profile)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .modifier(SidebarToggleHider())
        .frame(minWidth: 680, minHeight: 460)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task {
                    await loadSettings()
                }
            }
        }
    }

    @ViewBuilder
    private func settingsDetailView(for section: SettingsSection) -> some View {
        switch section {
        case .profile:
            ProfileSettingsView(viewModel: viewModel)
        case .system:
            SystemSettingsView(viewModel: viewModel)
        case .skills:
            SkillsSettingsView(viewModel: viewModel)
        case .shortcuts:
            ShortcutsSettingsView(viewModel: viewModel)
        case .things:
            ThingsSettingsView()
        case .memories:
            MemoriesSettingsView()
        case .api:
            APISettingsView(settings: viewModel.settings)
        }
    }

    private func loadSettings() async {
        await viewModel.load()
        await viewModel.loadSkills()
        await viewModel.loadShortcutsToken()
    }
}
#endif

#if os(macOS)
private struct SidebarToggleHider: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}
#endif

private struct SettingsTabsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var hasLoaded = false

    var body: some View {
        TabView {
            ProfileSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            SystemSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("System", systemImage: "slider.horizontal.3")
                }
            SkillsSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Skills", systemImage: "sparkles")
                }
            ShortcutsSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Shortcuts", systemImage: "bolt.horizontal.circle")
                }
            ThingsSettingsView()
                .tabItem {
                    Label("Things", systemImage: "checkmark.circle")
                }
            MemoriesSettingsView()
                .tabItem {
                    Label("Memories", systemImage: "brain")
                }
            APISettingsView(settings: viewModel.settings)
                .tabItem {
                    Label("API", systemImage: "link")
                }
        }
        .padding(16)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task {
                    await loadSettings()
                }
            }
        }
    }

    private func loadSettings() async {
        await viewModel.load()
        await viewModel.loadSkills()
        await viewModel.loadShortcutsToken()
    }
}

private struct ProfileSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isImagePickerPresented = false
    @State private var profileImage: Image?

    var body: some View {
        Form {
            Section("Profile") {
                HStack(spacing: 16) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile photo")
                            .font(.headline)
                        Text("Choose an image for your profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

#if os(iOS)
                Button("Change Photo") {
                    isImagePickerPresented = true
                }
                .sheet(isPresented: $isImagePickerPresented) {
                    ImagePicker(selectedImage: $profileImage)
                }
#else
                Text("Photo selection is available on iOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
#endif
            }

            Section("Appearance") {
                Text("Theme follows your system setting.")
                    .foregroundStyle(.secondary)
            }

            Section("Details") {
                LabeledContent("Name", value: displayValue(viewModel.settings?.name))
                LabeledContent("Job Title", value: displayValue(viewModel.settings?.jobTitle))
                LabeledContent("Employer", value: displayValue(viewModel.settings?.employer))
                LabeledContent("Pronouns", value: displayValue(viewModel.settings?.pronouns))
                LabeledContent("Location", value: displayValue(viewModel.settings?.location))
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await environment.container.authSession.signOut()
                        environment.refreshAuthState()
                    }
                } label: {
                    Text("Sign Out")
                }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.settings == nil {
                ProgressView()
            }
        }
    }

    private var profileAvatar: some View {
        Group {
            if let profileImage {
                profileImage
                    .resizable()
                    .scaledToFill()
            } else if let urlString = viewModel.settings?.profileImageUrl,
                      let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.2)))
        .accessibilityLabel("Profile photo")
    }

    private func displayValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not set" : trimmed
    }
}

private struct SystemSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("System") {
                LabeledContent("Communication Style", value: displayValue(viewModel.settings?.communicationStyle))
                LabeledContent("Working Relationship", value: displayValue(viewModel.settings?.workingRelationship))
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.settings == nil {
                ProgressView()
            }
        }
    }

    private func displayValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not set" : trimmed
    }
}

private struct SkillsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Text("Skills available to the assistant.")
                    .foregroundStyle(.secondary)
                Toggle("Enable All", isOn: Binding(
                    get: { allSkillsEnabled },
                    set: { isEnabled in
                        Task { await viewModel.setAllSkillsEnabled(isEnabled) }
                    }
                ))
                .disabled(viewModel.isSavingSkills || viewModel.isLoadingSkills || viewModel.settings == nil)
            }
            if let error = viewModel.skillsError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if viewModel.isSavingSkills {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
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
                            VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(skill.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { isSkillEnabled(skill.id) },
                                    set: { isEnabled in
                                        Task { await viewModel.setSkillEnabled(id: skill.id, enabled: isEnabled) }
                                    }
                                ))
                                .labelsHidden()
                                .disabled(viewModel.isSavingSkills || viewModel.settings == nil)
                            }
                            Text(skill.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .overlay {
            if viewModel.isLoadingSkills && viewModel.skills.isEmpty {
                ProgressView()
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
        let all = Set(viewModel.skills.map(\.id))
        return !all.isEmpty && enabled.isSuperset(of: all)
    }

    private func isSkillEnabled(_ id: String) -> Bool {
        viewModel.settings?.enabledSkills.contains(id) ?? false
    }
}

private struct MemoriesSettingsView: View {
    var body: some View {
        Form {
            Section("Memories") {
                Text("Manage memories in the Memories section.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ShortcutsSettingsView: View {
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
                        .foregroundStyle(.red)
                }
            }
        }
        .overlay {
            if viewModel.isLoadingShortcuts && viewModel.shortcutsToken.isEmpty {
                ProgressView()
            }
        }
    }

    private func copyToken() {
        guard !viewModel.shortcutsToken.isEmpty else { return }
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(viewModel.shortcutsToken, forType: .string)
        #else
        UIPasteboard.general.string = viewModel.shortcutsToken
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

private struct ThingsSettingsView: View {
    var body: some View {
        Form {
            Section("Things") {
                Text("Things integration uses native APIs on iOS and macOS.")
                    .foregroundStyle(.secondary)
                Text("If Things is not installed, this section will remain inactive.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct APISettingsView: View {
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
    }
}

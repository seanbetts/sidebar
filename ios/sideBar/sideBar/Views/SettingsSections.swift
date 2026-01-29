import LocalAuthentication
import sideBarShared
import SwiftUI
#if os(macOS)
import UniformTypeIdentifiers
#endif

// MARK: - SettingsSections

struct ProfileSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var isImagePickerPresented = false
    @State private var profileImage: Image?
    @State private var isProfileImageImporterPresented = false
    @State private var isUploadingProfileImage = false
    @State private var profileImageError: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile photo")
                            .font(.headline)
                        Text(photoSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
#if os(iOS)
                .contentShape(Rectangle())
                .onTapGesture {
                    isImagePickerPresented = true
                }
                .sheet(isPresented: $isImagePickerPresented) {
                    ImagePicker(selectedImage: $profileImage)
                }
#endif
#if os(macOS)
                .contentShape(Rectangle())
                .onTapGesture {
                    isProfileImageImporterPresented = true
                }
#endif
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Profile photo")
                .accessibilityHint("Double tap to change your profile photo.")
                .accessibilityAddTraits(.isButton)
            }

            #if os(macOS)
            if let profileImageError {
                Section {
                    Text(profileImageError)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }
            #endif

            Section {
                LabeledContent("Name", value: displayValue(viewModel.settings?.name))
                LabeledContent("Job Title", value: displayValue(viewModel.settings?.jobTitle))
                LabeledContent("Employer", value: displayValue(viewModel.settings?.employer))
                LabeledContent("Pronouns", value: displayValue(viewModel.settings?.pronouns))
                LabeledContent("Location", value: displayValue(viewModel.settings?.location))
            }

            Section {
                Button(role: .destructive) {
                    #if os(iOS)
                    dismiss()
                    #endif
                    Task { @MainActor in
                        await Task.yield()
                        await environment.beginSignOut()
                    }
                } label: {
                    Text("Sign Out")
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        #if os(macOS)
        .fileImporter(
            isPresented: $isProfileImageImporterPresented,
            allowedContentTypes: [.image]
        ) { result in
            Task {
                await handleProfileImageImport(result)
            }
        }
        #endif
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
            } else if let data = viewModel.profileImageData,
                      let image = loadProfileImage(from: data) {
                image
                    .resizable()
                    .scaledToFill()
            } else if viewModel.isLoadingProfileImage {
                ProgressView()
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

    private var photoSubtitle: String {
        #if os(macOS)
        return "Choose an image to update your profile photo."
        #else
        return "Tap to change."
        #endif
    }

#if os(macOS)
    private func handleProfileImageImport(_ result: Result<URL, Error>) async {
        profileImageError = nil
        do {
            let url = try result.get()
            let data = try Data(contentsOf: url)
            let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            let filename = url.lastPathComponent.isEmpty ? "profile-image" : url.lastPathComponent
            isUploadingProfileImage = true
            defer { isUploadingProfileImage = false }
            if let image = NSImage(contentsOf: url) {
                profileImage = Image(nsImage: image)
            }
            try await viewModel.uploadProfileImage(
                data: data,
                contentType: contentType,
                filename: filename
            )
        } catch {
            profileImageError = error.localizedDescription
        }
    }
#endif

    private func displayValue(_ value: String?) -> String {
        let trimmed = value?.trimmed ?? ""
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    private func loadProfileImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}

struct GeneralSettingsView: View {
    @AppStorage(AppStorageKeys.biometricUnlockEnabled) private var biometricUnlockEnabled = false
    @AppStorage(AppStorageKeys.weatherUsesFahrenheit) private var weatherUsesFahrenheit = false
    @State private var canUseDeviceAuth = false
    @State private var biometryType: LABiometryType = .none

    var body: some View {
        Form {
            Section("Security") {
                Toggle(biometricLabel, isOn: $biometricUnlockEnabled)
                    .disabled(!canUseDeviceAuth)
                if !canUseDeviceAuth {
                    Text("Set up Face ID or Touch ID to enable biometric unlock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Section("Weather") {
                Picker("Temperature Units", selection: $weatherUsesFahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #else
                .pickerStyle(.segmented)
                #endif
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear {
            evaluateBiometricSupport()
        }
    }

    private var biometricLabel: String {
        switch biometryType {
        case .faceID:
            return "Require Face ID"
        case .touchID:
            return "Require Touch ID"
        default:
            return "Require Biometric Unlock"
        }
    }

    private func evaluateBiometricSupport() {
        let context = LAContext()
        canUseDeviceAuth = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        biometryType = context.biometryType
    }
}

struct SystemSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Text("Customize the prompts that guide sideBar")
                    .foregroundStyle(.secondary)
            }
            Section("Communication Style") {
                Text(displayValue(viewModel.settings?.communicationStyle))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Working Relationship") {
                Text(displayValue(viewModel.settings?.workingRelationship))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .overlay {
            if viewModel.isLoading && viewModel.settings == nil {
                ProgressView()
            }
        }
    }

    private func displayValue(_ value: String?) -> String {
        let trimmed = value?.trimmed ?? ""
        return trimmed.isEmpty ? "Not set" : trimmed
    }
}

struct SkillsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Text("Manage installed skills and permissions here.")
                    .foregroundStyle(.secondary)
                Toggle("Enable all", isOn: Binding(
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
                        .foregroundStyle(DesignTokens.Colors.error)
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
                            Toggle(isOn: Binding(
                                get: { isSkillEnabled(skill.id) },
                                set: { isEnabled in
                                    Task { await viewModel.setSkillEnabled(id: skill.id, enabled: isEnabled) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(skill.name)
                                        .font(DesignTokens.Typography.subheadlineSemibold)
                                    Text(skill.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(viewModel.isSavingSkills || viewModel.settings == nil)
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
                ProgressView()
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

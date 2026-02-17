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
    @State private var name: String = ""
    @State private var jobTitle: String = ""
    @State private var employer: String = ""
    @State private var gender: String = ""
    @State private var pronouns: String = ""
    @State private var location: String = ""
    @State private var dateOfBirthEnabled: Bool = false
    @State private var dateOfBirth: Date = Date()
    @State private var hasLoadedDrafts = false
    @State private var isSyncingDrafts = false
    @State private var autosaveTask: Task<Void, Never>?

    private static let profileAutosaveDelayNs: UInt64 = 800_000_000
    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
                    ImagePicker(
                        selectedImage: $profileImage,
                        onImageDataPicked: { data, contentType, filename in
                            Task {
                                await uploadSelectedProfileImage(
                                    data: data,
                                    contentType: contentType,
                                    filename: filename
                                )
                            }
                        }
                    )
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

            if let profileImageError {
                Section {
                    Text(profileImageError)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }

            if let saveError = viewModel.profileSaveError {
                Section {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }

            if viewModel.isSavingProfile {
                Section {
                    HStack(spacing: 8) {
                        LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                        Text("Saving profile...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Profile") {
                TextField("Name", text: $name)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                TextField("Job Title", text: $jobTitle)
                TextField("Employer", text: $employer)
                TextField("Gender", text: $gender)
                TextField("Pronouns", text: $pronouns)
                TextField("Location", text: $location)
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
        .onAppear {
            syncDraftsFromSettings(viewModel.settings)
        }
        .onChange(of: profileAutosaveSignature) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: settingsSignature) { _, _ in
            syncDraftsFromSettings(viewModel.settings)
        }
        .onDisappear {
            flushPendingProfileAutosave()
        }
        .overlay {
            if viewModel.isLoading && viewModel.settings == nil {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
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
                LoadingIndicatorView(size: LoadingIndicatorSize.panel)
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
        if isUploadingProfileImage {
            return "Uploading..."
        }
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
            if let image = NSImage(contentsOf: url) {
                profileImage = Image(nsImage: image)
            }
            await uploadSelectedProfileImage(
                data: data,
                contentType: contentType,
                filename: filename
            )
        } catch {
            profileImageError = error.localizedDescription
        }
    }
#endif

    private func uploadSelectedProfileImage(
        data: Data,
        contentType: String,
        filename: String
    ) async {
        profileImageError = nil
        isUploadingProfileImage = true
        defer { isUploadingProfileImage = false }
        do {
            try await viewModel.uploadProfileImage(
                data: data,
                contentType: contentType,
                filename: filename
            )
        } catch {
            profileImageError = error.localizedDescription
        }
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

    private var settingsSignature: String {
        guard let settings = viewModel.settings else {
            return "none"
        }
        return [
            settings.name ?? "",
            settings.jobTitle ?? "",
            settings.employer ?? "",
            settings.gender ?? "",
            settings.pronouns ?? "",
            settings.location ?? "",
            settings.dateOfBirth ?? ""
        ].joined(separator: "|")
    }

    private var profileAutosaveSignature: String {
        [
            name,
            jobTitle,
            employer,
            gender,
            pronouns,
            location,
            dateOfBirthEnabled ? Self.dateString(from: dateOfBirth) : "nil"
        ].joined(separator: "|")
    }

    private var isDraftDirty: Bool {
        guard let settings = viewModel.settings else { return false }
        let currentDate = settings.dateOfBirth
        let nextDate = dateOfBirthEnabled ? Self.dateString(from: dateOfBirth) : nil
        return name != (settings.name ?? "")
            || jobTitle != (settings.jobTitle ?? "")
            || employer != (settings.employer ?? "")
            || gender != (settings.gender ?? "")
            || pronouns != (settings.pronouns ?? "")
            || location != (settings.location ?? "")
            || nextDate != currentDate
    }

    private func syncDraftsFromSettings(_ settings: UserSettings?) {
        guard let settings else { return }
        if hasLoadedDrafts && isDraftDirty {
            return
        }
        isSyncingDrafts = true
        name = settings.name ?? ""
        jobTitle = settings.jobTitle ?? ""
        employer = settings.employer ?? ""
        gender = settings.gender ?? ""
        pronouns = settings.pronouns ?? ""
        location = settings.location ?? ""
        if let parsedDate = Self.parseDate(settings.dateOfBirth) {
            dateOfBirthEnabled = true
            dateOfBirth = parsedDate
        } else {
            dateOfBirthEnabled = false
            dateOfBirth = Date()
        }
        hasLoadedDrafts = true
        isSyncingDrafts = false
    }

    private func scheduleAutosave() {
        guard hasLoadedDrafts, !isSyncingDrafts else { return }
        autosaveTask?.cancel()
        guard isDraftDirty else { return }
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: Self.profileAutosaveDelayNs)
            guard !Task.isCancelled else { return }
            await viewModel.saveProfileSettings(
                name: name,
                jobTitle: jobTitle,
                employer: employer,
                dateOfBirth: dateOfBirthEnabled ? dateOfBirth : nil,
                dateOfBirthEnabled: dateOfBirthEnabled,
                gender: gender,
                pronouns: pronouns,
                location: location
            )
        }
    }

    private func flushPendingProfileAutosave() {
        autosaveTask?.cancel()
        guard Self.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: hasLoadedDrafts,
            isSyncingDrafts: isSyncingDrafts,
            isDraftDirty: isDraftDirty,
            isSavingProfile: viewModel.isSavingProfile
        ) else {
            return
        }
        Task {
            await viewModel.saveProfileSettings(
                name: name,
                jobTitle: jobTitle,
                employer: employer,
                dateOfBirth: dateOfBirthEnabled ? dateOfBirth : nil,
                dateOfBirthEnabled: dateOfBirthEnabled,
                gender: gender,
                pronouns: pronouns,
                location: location
            )
        }
    }

    static func shouldFlushAutosaveOnDisappear(
        hasLoadedDrafts: Bool,
        isSyncingDrafts: Bool,
        isDraftDirty: Bool,
        isSavingProfile: Bool
    ) -> Bool {
        hasLoadedDrafts && !isSyncingDrafts && isDraftDirty && !isSavingProfile
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return dateParser.date(from: value)
    }

    private static func dateString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
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

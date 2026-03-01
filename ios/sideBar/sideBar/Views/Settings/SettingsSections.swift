import PhotosUI
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsSections

struct ProfileSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var profileImage: Image?
    @State private var isProfilePhotoSourceDialogPresented = false
    @State private var isProfilePhotoPickerPresented = false
    @State private var selectedProfilePhotoItem: PhotosPickerItem?
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
    @State private var draftsUserId: String?
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
                            .appFont(.headline)
                        Text(photoSubtitle)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isProfilePhotoSourceDialogPresented = true
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Profile photo")
                .accessibilityHint("Double tap to change your profile photo.")
                .accessibilityAddTraits(.isButton)
            }

            if let profileImageError {
                Section {
                    Text(profileImageError)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }

            if let saveError = viewModel.profileSaveError {
                Section {
                    Text(saveError)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }

            Section("Profile") {
                LabeledContent("Name") {
                    TextField("Not set", text: $name)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
                LabeledContent("Job Title") {
                    TextField("Not set", text: $jobTitle)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Employer") {
                    TextField("Not set", text: $employer)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Gender") {
                    Picker("Gender", selection: $gender) {
                        Text("Not set").appFont(.body).tag("")
                        ForEach(genderPickerOptions, id: \.self) { option in
                            Text(option).appFont(.body).tag(option)
                        }
                    }
                    .appFont(.body)
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .appFont(.body)
                LabeledContent("Pronouns") {
                    Picker("Pronouns", selection: $pronouns) {
                        Text("Not set").appFont(.body).tag("")
                        ForEach(pronounPickerOptions, id: \.self) { option in
                            Text(option).appFont(.body).tag(option)
                        }
                    }
                    .appFont(.body)
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .appFont(.body)
                LabeledContent("Location") {
                    TextField("Not set", text: $location)
                        .multilineTextAlignment(.trailing)
                }
                ProfileDateOfBirthField(
                    dateOfBirthEnabled: $dateOfBirthEnabled,
                    dateOfBirth: $dateOfBirth
                )
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
        .confirmationDialog(
            "Change Profile Photo",
            isPresented: $isProfilePhotoSourceDialogPresented
        ) {
            Button("Choose from Photos") {
                isProfilePhotoPickerPresented = true
            }
            Button("Choose from Files") {
                isProfileImageImporterPresented = true
            }
            Button("Cancel", role: .cancel) {
            }
        }
        .photosPicker(
            isPresented: $isProfilePhotoPickerPresented,
            selection: $selectedProfilePhotoItem,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: selectedProfilePhotoItem) { _, item in
            guard let item else { return }
            Task {
                await handleProfilePhotoSelection(item)
                selectedProfilePhotoItem = nil
            }
        }
        .fileImporter(
            isPresented: $isProfileImageImporterPresented,
            allowedContentTypes: [.image]
        ) { result in
            Task {
                await handleProfileImageImport(result)
            }
        }
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

    private var genderPickerOptions: [String] {
        Self.pickerOptions(base: Self.genderOptions, currentValue: gender)
    }

    private var pronounPickerOptions: [String] {
        Self.pickerOptions(base: Self.pronounOptions, currentValue: pronouns)
    }

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
            settings.userId,
            settings.name ?? "",
            settings.jobTitle ?? "",
            settings.employer ?? "",
            settings.gender ?? "",
            settings.pronouns ?? "",
            settings.location ?? "",
            settings.dateOfBirth ?? ""
        ].compactMap { $0 }.joined(separator: "|")
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
            || !Self.pickerValuesEquivalent(gender, settings.gender)
            || !Self.pickerValuesEquivalent(pronouns, settings.pronouns)
            || location != (settings.location ?? "")
            || nextDate != currentDate
    }

    private func syncDraftsFromSettings(_ settings: UserSettings?) {
        guard let settings else { return }
        let shouldSync = Self.shouldSyncDrafts(
            hasLoadedDrafts: hasLoadedDrafts,
            isDraftDirty: isDraftDirty,
            previousUserId: draftsUserId,
            nextUserId: settings.userId
        )
        if !shouldSync {
            return
        }
        if Self.normalizedUserId(draftsUserId) != Self.normalizedUserId(settings.userId) {
            autosaveTask?.cancel()
        }
        isSyncingDrafts = true
        name = settings.name ?? ""
        jobTitle = settings.jobTitle ?? ""
        employer = settings.employer ?? ""
        gender = Self.normalizedPickerSelection(currentValue: settings.gender, base: Self.genderOptions)
        pronouns = Self.normalizedPickerSelection(currentValue: settings.pronouns, base: Self.pronounOptions)
        location = settings.location ?? ""
        if let parsedDate = Self.parseDate(settings.dateOfBirth) {
            dateOfBirthEnabled = true
            dateOfBirth = parsedDate
        } else {
            dateOfBirthEnabled = false
            dateOfBirth = Date()
        }
        draftsUserId = settings.userId
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

    static func shouldSyncDrafts(
        hasLoadedDrafts: Bool,
        isDraftDirty: Bool,
        previousUserId: String?,
        nextUserId: String?
    ) -> Bool {
        let didChangeUser = normalizedUserId(previousUserId) != normalizedUserId(nextUserId)
        return didChangeUser || !hasLoadedDrafts || !isDraftDirty
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return dateParser.date(from: value)
    }

    private static func normalizedUserId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func dateString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private extension ProfileSettingsView {
    func handleProfilePhotoSelection(_ item: PhotosPickerItem) async {
        profileImageError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(
                    domain: "ProfilePhotoSelection",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Couldn’t load selected photo data."]
                )
            }
            if let image = loadProfileImage(from: data) {
                profileImage = image
            }
            let contentType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            await uploadSelectedProfileImage(
                data: data,
                contentType: contentType,
                filename: "profile-image.\(fileExtension)"
            )
        } catch {
            profileImageError = error.localizedDescription
        }
    }

    func handleProfileImageImport(_ result: Result<URL, Error>) async {
        profileImageError = nil
        do {
            let url = try result.get()
            let data = try loadImageData(from: url)
            let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            let filename = url.lastPathComponent.isEmpty ? "profile-image" : url.lastPathComponent
            if let image = loadProfileImage(from: data) {
                profileImage = image
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

    func loadImageData(from url: URL) throws -> Data {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }
}

import PhotosUI
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers

extension ProfileSettingsView {
    var profileAvatar: some View {
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

    var photoSubtitle: String {
        if isUploadingProfileImage {
            return "Uploading..."
        }
        #if os(macOS)
        return "Choose an image to update your profile photo."
        #else
        return "Tap to change."
        #endif
    }

    var genderPickerOptions: [String] {
        Self.pickerOptions(base: Self.genderOptions, currentValue: gender)
    }

    var pronounPickerOptions: [String] {
        Self.pickerOptions(base: Self.pronounOptions, currentValue: pronouns)
    }

    func uploadSelectedProfileImage(
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

    func loadProfileImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }

    var settingsSignature: String {
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

    var profileAutosaveSignature: String {
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

    var isDraftDirty: Bool {
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

    func syncDraftsFromSettings(_ settings: UserSettings?) {
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

    func scheduleAutosave() {
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

    func flushPendingProfileAutosave() {
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

    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return dateParser.date(from: value)
    }

    static func normalizedUserId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func dateString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension ProfileSettingsView {
    @ViewBuilder
    var genderField: some View {
        #if os(macOS)
        SettingsMacFieldRow("Gender") {
            Picker("Gender", selection: $gender) {
                Text("Not set").tag("")
                ForEach(genderPickerOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 320, alignment: .trailing)
        }
        .appFont(.body)
        #else
        LabeledContent("Gender") {
            ProfileStringSelectorMenu(selection: $gender, options: genderPickerOptions)
        }
        .appFont(.body)
        #endif
    }

    @ViewBuilder
    var pronounsField: some View {
        #if os(macOS)
        SettingsMacFieldRow("Pronouns") {
            Picker("Pronouns", selection: $pronouns) {
                Text("Not set").tag("")
                ForEach(pronounPickerOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 320, alignment: .trailing)
        }
        .appFont(.body)
        #else
        LabeledContent("Pronouns") {
            ProfileStringSelectorMenu(selection: $pronouns, options: pronounPickerOptions)
        }
        .appFont(.body)
        #endif
    }

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

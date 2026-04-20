import PhotosUI
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers

extension ProfileSettingsView {
    static let maxProfileImageUploadBytes = 5 * 1024 * 1024

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
            profileImageError = profileImageUploadErrorMessage(for: error)
        }
    }

    var failedProfileImageWriteSignature: String {
        environment.writeQueue.failedHeaderRows
            .filter {
                $0.entityType == WriteEntityType.settings.rawValue
                    && $0.entityId == SettingsMutationPayload.profileImageEntityID
            }
            .map { "\($0.id.uuidString)|\($0.lastError ?? "")|\($0.attempts)" }
            .joined(separator: "||")
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
        return profileDraftState.isDirty(comparedTo: settings)
    }

    func syncDraftsFromSettings(_ settings: UserSettings?) {
        guard let settings else { return }
        let shouldSync = SettingsDraftSynchronizer.shouldSyncDrafts(
            hasLoadedDrafts: hasLoadedDrafts,
            isDraftDirty: profileDraftState.isDirty(comparedTo: settings),
            previousUserId: draftsUserId,
            nextUserId: settings.userId
        )
        if !shouldSync {
            return
        }
        if SettingsDraftSynchronizer.normalizedUserId(draftsUserId) != SettingsDraftSynchronizer.normalizedUserId(settings.userId) {
            autosaveTask?.cancel()
        }
        isSyncingDrafts = true
        applyDraftState(.from(settings: settings))
        draftsUserId = settings.userId
        hasLoadedDrafts = true
        isSyncingDrafts = false
    }

    private var profileDraftState: ProfileDraftState {
        .init(
            name: name,
            jobTitle: jobTitle,
            employer: employer,
            gender: gender,
            pronouns: pronouns,
            location: location,
            dateOfBirth: dateOfBirthEnabled ? Self.dateString(from: dateOfBirth) : nil
        )
    }

    private func applyDraftState(_ state: ProfileDraftState) {
        name = state.name
        jobTitle = state.jobTitle
        employer = state.employer
        gender = state.gender
        pronouns = state.pronouns
        location = state.location
        if let dateString = state.dateOfBirth,
           let parsedDate = Self.parseDate(dateString) {
            dateOfBirthEnabled = true
            dateOfBirth = parsedDate
        } else {
            dateOfBirthEnabled = false
            dateOfBirth = Date()
        }
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
        SettingsDraftSynchronizer.shouldSyncDrafts(
            hasLoadedDrafts: hasLoadedDrafts,
            isDraftDirty: isDraftDirty,
            previousUserId: previousUserId,
            nextUserId: nextUserId
        )
    }

    static func normalizedUserId(_ value: String?) -> String? {
        SettingsDraftSynchronizer.normalizedUserId(value)
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return dateParser.date(from: value)
    }

    static func dateString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

struct SettingsDraftSynchronizer {
    static func shouldSyncDrafts(
        hasLoadedDrafts: Bool,
        isDraftDirty: Bool,
        previousUserId: String?,
        nextUserId: String?
    ) -> Bool {
        let didChangeUser = normalizedUserId(previousUserId) != normalizedUserId(nextUserId)
        return didChangeUser || !hasLoadedDrafts || !isDraftDirty
    }

    static func normalizedUserId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension ProfileSettingsView {
    struct ProfileDraftState {
        let name: String
        let jobTitle: String
        let employer: String
        let gender: String
        let pronouns: String
        let location: String
        let dateOfBirth: String?

        static func from(settings: UserSettings) -> ProfileDraftState {
            .init(
                name: normalizedTextFieldValue(settings.name),
                jobTitle: normalizedTextFieldValue(settings.jobTitle),
                employer: normalizedTextFieldValue(settings.employer),
                gender: normalizedPickerSelection(currentValue: settings.gender, base: genderOptions),
                pronouns: normalizedPickerSelection(currentValue: settings.pronouns, base: pronounOptions),
                location: normalizedTextFieldValue(settings.location),
                dateOfBirth: settings.dateOfBirth
            )
        }

        func isDirty(comparedTo settings: UserSettings) -> Bool {
            if name != Self.normalizedTextFieldValue(settings.name) { return true }
            if jobTitle != Self.normalizedTextFieldValue(settings.jobTitle) { return true }
            if employer != Self.normalizedTextFieldValue(settings.employer) { return true }
            if !ProfileSettingsView.pickerValuesEquivalent(gender, settings.gender) { return true }
            if !ProfileSettingsView.pickerValuesEquivalent(pronouns, settings.pronouns) { return true }
            if location != Self.normalizedTextFieldValue(settings.location) { return true }
            if dateOfBirth != settings.dateOfBirth { return true }
            return false
        }

        private static func normalizedTextFieldValue(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    @ViewBuilder
    var genderField: some View {
        FormField("Gender") {
            ProfileStringSelectorMenu(
                selection: $gender,
                options: genderPickerOptions,
                selectionLabel: "Gender"
            )
        }
    }

    @ViewBuilder
    var pronounsField: some View {
        FormField("Pronouns") {
            ProfileStringSelectorMenu(
                selection: $pronouns,
                options: pronounPickerOptions,
                selectionLabel: "Pronouns"
            )
        }
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
            if let validationMessage = Self.profileImageValidationMessage(for: data) {
                profileImageError = validationMessage
                return
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
            profileImageError = profileImageUploadErrorMessage(for: error)
        }
    }

    func handleProfileImageImport(_ result: Result<URL, Error>) async {
        profileImageError = nil
        do {
            let url = try result.get()
            let data = try loadImageData(from: url)
            if let validationMessage = Self.profileImageValidationMessage(for: data) {
                profileImageError = validationMessage
                return
            }
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
            profileImageError = profileImageUploadErrorMessage(for: error)
        }
    }

    func profileImageUploadErrorMessage(for error: Error) -> String {
        ErrorMapping.presentation(
            for: error,
            operation: "settings.profileImage.upload",
            requestKind: .multipartUpload
        ).message
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

    func syncQueuedProfileImageError() {
        queuedProfileImageError = Self.profileImageQueueFailureMessage(from: environment.writeQueue.failedHeaderRows)
    }

    static func profileImageValidationMessage(for data: Data) -> String? {
        guard data.count > maxProfileImageUploadBytes else {
            return nil
        }
        return "Profile photo is too large. Choose an image smaller than 5MB."
    }

    static func profileImageQueueFailureMessage(from summaries: [PendingWriteSummary]) -> String? {
        guard let summary = summaries.first(where: {
            $0.entityType == WriteEntityType.settings.rawValue
                && $0.entityId == SettingsMutationPayload.profileImageEntityID
        }),
        let errorDescription = summary.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
        !errorDescription.isEmpty else {
            return nil
        }

        if let apiError = storedAPIClientError(from: errorDescription) {
            return ErrorMapping.message(for: apiError)
        }

        return errorDescription
    }

    private static func storedAPIClientError(from description: String) -> APIClientError? {
        switch description {
        case "invalidUrl":
            return .invalidUrl
        case "missingToken":
            return .missingToken
        case "decodingFailed":
            return .decodingFailed
        case "unknown":
            return .unknown
        default:
            break
        }

        if description.hasPrefix("requestFailed("), description.hasSuffix(")"),
           let status = Int(description.dropFirst("requestFailed(".count).dropLast()) {
            return .requestFailed(status)
        }

        if description.hasPrefix("apiError(\""), description.hasSuffix("\")") {
            let quotedMessage = description
                .dropFirst("apiError(\"".count)
                .dropLast(2)
            let message = quotedMessage.replacingOccurrences(of: "\\\"", with: "\"")
            return .apiError(message)
        }

        return nil
    }
}

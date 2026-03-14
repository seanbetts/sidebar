import PhotosUI
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsSections

struct ProfileSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject var environment: AppEnvironment
    @Environment(\.dismiss) var dismiss
    @State var profileImage: Image?
    @State var isProfilePhotoSourceDialogPresented = false
    @State var isProfilePhotoPickerPresented = false
    @State var selectedProfilePhotoItem: PhotosPickerItem?
    @State var isProfileImageImporterPresented = false
    @State var isUploadingProfileImage = false
    @State var profileImageError: String?
    @State var name: String = ""
    @State var jobTitle: String = ""
    @State var employer: String = ""
    @State var gender: String = ""
    @State var pronouns: String = ""
    @State var location: String = ""
    @State var dateOfBirthEnabled: Bool = false
    @State var dateOfBirth: Date = Date()
    @State var hasLoadedDrafts = false
    @State var isSyncingDrafts = false
    @State var draftsUserId: String?
    @State var autosaveTask: Task<Void, Never>?

    static let profileAutosaveDelayNs: UInt64 = 800_000_000
    static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        #if os(macOS)
        macProfileForm
        #else
        iosProfileForm
        #endif
    }

    #if os(macOS)
    private var macProfileForm: some View {
        Form {
            macProfilePhotoSection
            profileImageErrorSection
            profileSaveErrorSection
            macProfileDetailsSection
            macSignOutSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.settingsBackground)
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
    #endif

    private var iosProfileForm: some View {
        Form {
            iosProfilePhotoSection
            profileImageErrorSection
            profileSaveErrorSection
            iosProfileDetailsSection
            iosSignOutSection
        }
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

    #if os(macOS)
    private var macProfilePhotoSection: some View {
        Section {
            SettingsMacSectionIntro(
                title: "Profile photo",
                message: "Choose an image that sideBar can use across tasks, notes, and assistant context."
            )
            SettingsMacHeroButtonRow(
                title: "Profile photo",
                subtitle: photoSubtitle,
                action: { isProfilePhotoSourceDialogPresented = true },
                leading: {
                profileAvatar
                }
            )
        }
    }

    private var macProfileDetailsSection: some View {
        Section {
            SettingsMacSectionIntro(
                title: "Personal details",
                message: "Keep the details your assistant can reference during planning, writing, and personalization up to date."
            )
            SettingsMacFieldRow("Name") {
                TextField("Not set", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }
            SettingsMacFieldRow("Job Title") {
                TextField("Not set", text: $jobTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }
            SettingsMacFieldRow("Employer") {
                TextField("Not set", text: $employer)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }
            genderField
            pronounsField
            SettingsMacFieldRow("Location") {
                TextField("Not set", text: $location)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }
            ProfileDateOfBirthField(
                dateOfBirthEnabled: $dateOfBirthEnabled,
                dateOfBirth: $dateOfBirth
            )
        }
    }

    private var macSignOutSection: some View {
        Section {
            SettingsMacActionSection(
                title: "Account",
                message: "Sign out on this Mac if you need to switch workspace context or disconnect this device."
            ) {
                Button(role: .destructive) {
                    Task { @MainActor in
                        await Task.yield()
                        await environment.beginSignOut()
                    }
                } label: {
                    Text("Sign Out")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Colors.actionDestructive)
            }
        }
    }
    #endif

    private var iosProfilePhotoSection: some View {
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
    }

    @ViewBuilder
    private var profileImageErrorSection: some View {
        if let profileImageError {
            Section {
                #if os(macOS)
                SettingsMacStatusBanner(message: profileImageError, tone: .error)
                #else
                Text(profileImageError)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                #endif
            }
        }
    }

    @ViewBuilder
    private var profileSaveErrorSection: some View {
        if let saveError = viewModel.profileSaveError {
            Section {
                #if os(macOS)
                SettingsMacStatusBanner(message: saveError, tone: .error)
                #else
                Text(saveError)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                #endif
            }
        }
    }

    private var iosProfileDetailsSection: some View {
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
            genderField
            pronounsField
            LabeledContent("Location") {
                TextField("Not set", text: $location)
                    .multilineTextAlignment(.trailing)
            }
            ProfileDateOfBirthField(
                dateOfBirthEnabled: $dateOfBirthEnabled,
                dateOfBirth: $dateOfBirth
            )
        }
    }

    private var iosSignOutSection: some View {
        Section {
            Button(role: .destructive) {
                dismiss()
                Task { @MainActor in
                    await Task.yield()
                    await environment.beginSignOut()
                }
            } label: {
                Text("Sign Out")
            }
        }
    }

}

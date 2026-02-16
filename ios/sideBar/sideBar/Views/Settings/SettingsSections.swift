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
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isPendingWritesPresented = false

    var body: some View {
        Form {
            if environment.writeQueue.pendingCount > 0 || environment.writeQueue.isProcessing {
                Section("Sync Status") {
                    HStack(spacing: 8) {
                        SyncStatusIndicator()
                        Text(pendingStatusText)
                            .font(DesignTokens.Typography.labelMd)
                    }
                    Button("View pending changes") {
                        isPendingWritesPresented = true
                    }
                }
            }
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
        .sheet(isPresented: $isPendingWritesPresented) {
            NavigationStack {
                PendingWritesView()
            }
            .phoneSheetGrabBarVisible()
        }
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

    private var pendingStatusText: String {
        if environment.writeQueue.isProcessing {
            return "Syncing \(environment.writeQueue.pendingCount) changes"
        }
        return "\(environment.writeQueue.pendingCount) pending changes"
    }
}

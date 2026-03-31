import LocalAuthentication
import sideBarShared
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct GeneralSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    enum TextSizeControlMode: Equatable {
        case picker
        case menuPicker
    }

    enum TextSizeControlPlatform {
        case iOS
        case macOS
    }

    @AppStorage(AppStorageKeys.biometricUnlockEnabled) private var biometricUnlockEnabled = false
    @AppStorage(AppStorageKeys.weatherUsesFahrenheit) private var weatherUsesFahrenheit = false
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue
    @State private var canUseDeviceAuth = false
    @State private var biometryType: LABiometryType = .none
    @State private var diagnosticsStatusMessage: String?
    @State private var isPasswordChangePresented = false
    @State private var isStartingPasswordChange = false
    @State private var passwordChangeAuthFailure: LocalDeviceAuthenticationFailure?
    private let localDeviceAuthenticator: any LocalDeviceAuthenticating

    static func textSizeControlMode(for platform: TextSizeControlPlatform) -> TextSizeControlMode {
        switch platform {
        case .iOS:
            return .picker
        case .macOS:
            return .menuPicker
        }
    }

    init(localDeviceAuthenticator: (any LocalDeviceAuthenticating)? = nil) {
        self.localDeviceAuthenticator = localDeviceAuthenticator ?? LocalDeviceAuthenticator()
    }

    var body: some View {
        #if os(macOS)
        macGeneralForm
        #else
        iosGeneralForm
        #endif
    }

    #if os(macOS)
    private var macGeneralForm: some View {
        Form {
            Section {
                SettingsMacSectionIntro(
                    title: "Text",
                    message: "Choose how dense sideBar should feel across panels, editors, and assistant surfaces."
                )
                textSizeControl
            }

            Section {
                SettingsMacActionSection(
                    title: "Security",
                    message: "Protect the app when your Mac supports biometric authentication."
                ) {
                    Toggle(biometricLabel, isOn: $biometricUnlockEnabled)
                        .disabled(!canUseDeviceAuth)

                    Button {
                        startPasswordChangeFlow()
                    } label: {
                        Text("Change password")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isStartingPasswordChange || environment.authState != .active)

                    if !canUseDeviceAuth {
                        SettingsMacStatusBanner(
                            message: "Set up Face ID or Touch ID to enable biometric unlock.",
                            tone: .info
                        )
                    }
                }
            }

            Section {
                SettingsMacSectionIntro(
                    title: "Weather",
                    message: "Pick the temperature unit sideBar should use when weather context is shown."
                )
                Picker("Temperature Units", selection: $weatherUsesFahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                .appFont(.body)
                .pickerStyle(settingsMacWeatherPickerStyle())
            }

            Section {
                SettingsMacActionSection(
                    title: "Diagnostics",
                    message: "Capture or clear the external-surface diagnostics used to debug share extensions and related app flows."
                ) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Button("Copy External Surface Diagnostics") {
                            copyExternalSurfaceDiagnostics()
                        }
                        .buttonStyle(.bordered)

                        Button("Clear External Surface Diagnostics") {
                            clearExternalSurfaceDiagnostics()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let diagnosticsStatusMessage {
                        SettingsMacStatusBanner(message: diagnosticsStatusMessage, tone: .info)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.settingsBackground)
        .onAppear {
            appTextSizeRaw = AppTextSizeOption.resolved(from: appTextSizeRaw).rawValue
            evaluateBiometricSupport()
        }
    }
    #endif

    private var iosGeneralForm: some View {
        Form {
            Section("Text") {
                textSizeControl
            }
            Section("Security") {
                Toggle(biometricLabel, isOn: $biometricUnlockEnabled)
                    .disabled(!canUseDeviceAuth)
                Button {
                    startPasswordChangeFlow()
                } label: {
                    Text("Change password")
                }
                .disabled(isStartingPasswordChange || environment.authState != .active)
                if !canUseDeviceAuth {
                    Text("Set up Face ID or Touch ID to enable biometric unlock.")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Weather") {
                Picker("Temperature Units", selection: $weatherUsesFahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                .appFont(.body)
                .pickerStyle(.segmented)
            }
            Section("Diagnostics") {
                Button("Copy External Surface Diagnostics") {
                    copyExternalSurfaceDiagnostics()
                }
                Button("Clear External Surface Diagnostics") {
                    clearExternalSurfaceDiagnostics()
                }
                if let diagnosticsStatusMessage {
                    Text(diagnosticsStatusMessage)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            appTextSizeRaw = AppTextSizeOption.resolved(from: appTextSizeRaw).rawValue
            evaluateBiometricSupport()
        }
        .sheet(isPresented: $isPasswordChangePresented) {
            SettingsPasswordChangeView()
                .environmentObject(environment)
        }
        .alert(item: $passwordChangeAuthFailure) { failure in
            if failure.showsSettingsAction {
                Alert(
                    title: Text("Authentication unavailable"),
                    message: Text(failure.message),
                    primaryButton: .default(Text("Enable in Settings"), action: openSystemSettings),
                    secondaryButton: .cancel()
                )
            } else {
                Alert(
                    title: Text("Authentication failed"),
                    message: Text(failure.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    @ViewBuilder
    private var textSizeControl: some View {
        switch Self.textSizeControlMode(for: currentTextSizeControlPlatform) {
        case .picker:
            Picker("Text Size", selection: $appTextSizeRaw) {
                textSizePickerOptions
            }
            .appFont(.body)
        case .menuPicker:
            Picker("Text Size", selection: $appTextSizeRaw) {
                textSizePickerOptions
            }
            .appFont(.body)
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var textSizePickerOptions: some View {
        ForEach(AppTextSizeOption.allCases) { option in
            Text(option.displayName)
                .appFont(.body)
                .tag(option.rawValue)
        }
    }

    private var currentTextSizeControlPlatform: TextSizeControlPlatform {
        #if os(iOS)
        .iOS
        #else
        .macOS
        #endif
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

    private func copyExternalSurfaceDiagnostics() {
        let payload = ExternalSurfaceDiagnosticsStore.shared.exportText()
        guard !payload.isEmpty else {
            diagnosticsStatusMessage = "No external surface diagnostics have been recorded yet."
            return
        }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = payload
        #endif

        diagnosticsStatusMessage = "Copied recent external surface diagnostics."
    }

    private func clearExternalSurfaceDiagnostics() {
        ExternalSurfaceDiagnosticsStore.shared.clear()
        diagnosticsStatusMessage = "Cleared external surface diagnostics."
    }

    private func startPasswordChangeFlow() {
        guard !isStartingPasswordChange else { return }
        isStartingPasswordChange = true
        passwordChangeAuthFailure = nil

        Task {
            let result = await localDeviceAuthenticator.authenticateForSensitiveAction(
                reason: "Confirm it's you before changing your password."
            )
            await MainActor.run {
                isStartingPasswordChange = false
                switch result {
                case .success:
                    isPasswordChangePresented = true
                case .cancelled:
                    break
                case .failure(let failure):
                    passwordChangeAuthFailure = failure
                }
            }
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        guard let url = URL(string: "x-apple.systempreferences:") else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
}

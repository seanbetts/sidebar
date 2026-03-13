import LocalAuthentication
import sideBarShared
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct GeneralSettingsView: View {
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
    #if DEBUG
    @State private var isSentryCrashConfirmationPresented = false
    #endif

    static func textSizeControlMode(for platform: TextSizeControlPlatform) -> TextSizeControlMode {
        switch platform {
        case .iOS:
            return .picker
        case .macOS:
            return .menuPicker
        }
    }

    var body: some View {
        Form {
            Section("Text") {
                textSizeControl
            }
            Section("Security") {
                Toggle(biometricLabel, isOn: $biometricUnlockEnabled)
                    .disabled(!canUseDeviceAuth)
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
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #else
                .pickerStyle(.segmented)
                #endif
            }
            Section("Diagnostics") {
                Button("Copy External Surface Diagnostics") {
                    copyExternalSurfaceDiagnostics()
                }
                Button("Clear External Surface Diagnostics") {
                    clearExternalSurfaceDiagnostics()
                }
                #if DEBUG
                Button("Send Sentry Test Crash", role: .destructive) {
                    isSentryCrashConfirmationPresented = true
                }
                Text("Crashes the app immediately. Launch without Xcode attached, then relaunch once so Sentry can send the crash.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                #endif
                if let diagnosticsStatusMessage {
                    Text(diagnosticsStatusMessage)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear {
            appTextSizeRaw = AppTextSizeOption.resolved(from: appTextSizeRaw).rawValue
            evaluateBiometricSupport()
        }
        #if DEBUG
        .confirmationDialog(
            "Send Sentry Test Crash?",
            isPresented: $isSentryCrashConfirmationPresented
        ) {
            Button("Crash App Now", role: .destructive) {
                _ = SentryBootstrap.triggerDebugTestCrash()
            }
            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text("This will terminate the app immediately. Launch again afterward so the crash can be sent to Sentry.")
        }
        #endif
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
}

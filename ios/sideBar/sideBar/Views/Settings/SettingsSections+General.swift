import LocalAuthentication
import sideBarShared
import SwiftUI

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
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear {
            appTextSizeRaw = AppTextSizeOption.resolved(from: appTextSizeRaw).rawValue
            evaluateBiometricSupport()
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
}

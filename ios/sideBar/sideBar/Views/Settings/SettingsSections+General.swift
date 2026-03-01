import LocalAuthentication
import sideBarShared
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AppStorageKeys.biometricUnlockEnabled) private var biometricUnlockEnabled = false
    @AppStorage(AppStorageKeys.weatherUsesFahrenheit) private var weatherUsesFahrenheit = false
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue
    @State private var canUseDeviceAuth = false
    @State private var biometryType: LABiometryType = .none

    var body: some View {
        Form {
            Section("Text") {
                Picker("Text Size", selection: $appTextSizeRaw) {
                    ForEach(AppTextSizeOption.allCases) { option in
                        Text(option.displayName)
                            .appFont(.body)
                            .tag(option.rawValue)
                    }
                }
                .appFont(.body)
                #if os(macOS)
                .pickerStyle(.menu)
                #endif
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

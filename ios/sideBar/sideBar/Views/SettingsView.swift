import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $environment.themeManager.mode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(16)
    }
}

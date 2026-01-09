import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    public init() {
    }

    public var body: some View {
        Form {
            Section("Appearance") {
                Text("Theme follows your system setting.")
                    .foregroundStyle(.secondary)
            }
#if DEBUG
            Section("Debug") {
                HStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                        Text("AppLogo")
                            .font(.caption)
                    }
                    VStack(spacing: 8) {
                        Image("AppLogoDark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                        Text("AppLogoDark")
                            .font(.caption)
                    }
                }
                Text("Color scheme: \(colorScheme == .dark ? "dark" : "light")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
#endif
        }
        .padding(16)
    }
}

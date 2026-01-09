import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        TabView {
            ProfileSettingsView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            MemoriesSettingsView()
                .tabItem {
                    Label("Memories", systemImage: "brain")
                }
            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "bolt.horizontal.circle")
                }
            APISettingsView()
                .tabItem {
                    Label("API", systemImage: "link")
                }
        }
        .padding(16)
    }
}

private struct ProfileSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isImagePickerPresented = false
    @State private var profileImage: Image?

    var body: some View {
        Form {
            Section("Profile") {
                HStack(spacing: 16) {
                    profileImage?
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.2)))
                        .accessibilityLabel("Profile photo")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile photo")
                            .font(.headline)
                        Text("Choose an image for your profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

#if os(iOS)
                Button("Change Photo") {
                    isImagePickerPresented = true
                }
                .sheet(isPresented: $isImagePickerPresented) {
                    ImagePicker(selectedImage: $profileImage)
                }
#else
                Text("Photo selection is available on iOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
#endif
            }

            Section("Appearance") {
                Text("Theme follows your system setting.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await environment.container.authSession.signOut()
                        environment.refreshAuthState()
                    }
                } label: {
                    Text("Sign Out")
                }
            }
        }
    }
}

private struct MemoriesSettingsView: View {
    var body: some View {
        Form {
            Section("Memories") {
                Text("Memories settings will appear here.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("Shortcuts") {
                Text("Shortcuts settings will appear here.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct APISettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section("API") {
                Text("API settings will appear here.")
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
                        Text("AppLogo (system)")
                            .font(.caption)
                    }
                    VStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .environment(\.colorScheme, .dark)
                        Text("AppLogo (forced dark)")
                            .font(.caption)
                    }
                }
                Text("Color scheme: \(colorScheme == .dark ? "dark" : "light")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
#endif
        }
    }
}

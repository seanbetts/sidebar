import SwiftUI

struct ProfileAvatarView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let size: CGFloat

    var body: some View {
        Group {
            if environment.isAuthenticated,
               let data = environment.settingsViewModel.profileImageData,
               let image = loadProfileImage(from: data) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: size * 0.7, weight: .regular))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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

struct SettingsAvatarButton: View {
    @EnvironmentObject private var environment: AppEnvironment
    let size: CGFloat

    init(size: CGFloat = 28) {
        self.size = size
    }

    var body: some View {
        Button {
            environment.commandSelection = .settings
        } label: {
            ProfileAvatarView(size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}

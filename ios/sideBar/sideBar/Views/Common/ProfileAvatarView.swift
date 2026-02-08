import SwiftUI

struct ProfileAvatarView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let size: CGFloat
    @State private var cachedImage: Image?
    @State private var cachedHash: Int?

    var body: some View {
        Group {
            if environment.isAuthenticated, let cachedImage {
                cachedImage
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: size * 0.7, weight: .regular))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onAppear(perform: updateCachedImage)
        .onChange(of: environment.settingsViewModel.profileImageData) { _, _ in
            updateCachedImage()
        }
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

    private func updateCachedImage() {
        guard environment.isAuthenticated,
              let data = environment.settingsViewModel.profileImageData else {
            cachedImage = nil
            cachedHash = nil
            return
        }

        let newHash = data.hashValue
        guard cachedHash != newHash else { return }
        cachedHash = newHash
        cachedImage = loadProfileImage(from: data)
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

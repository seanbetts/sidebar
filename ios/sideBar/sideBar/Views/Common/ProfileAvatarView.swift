import SwiftUI
#if os(iOS)
import UIKit
#endif

enum GlobalAvatarRegionMetrics {
    static let symbolScaleFactor: CGFloat = 0.7
}

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
                    .appScaledFont(
                        size: size * GlobalAvatarRegionMetrics.symbolScaleFactor,
                        weight: .regular
                    )
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

struct GlobalAvatarRegionControls: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isScratchpadPresented = false
    let avatarSize: CGFloat

    init(avatarSize: CGFloat = 28) {
        self.avatarSize = avatarSize
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Button(action: handleScratchpadTap) {
                Image(systemName: "square.and.pencil")
                    .appScaledFont(
                        size: avatarSize * GlobalAvatarRegionMetrics.symbolScaleFactor,
                        weight: .regular
                    )
                    .frame(width: avatarSize, height: avatarSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scratchpad")
            .popover(
                isPresented: $isScratchpadPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                ScratchpadPopoverSurface(
                    api: environment.container.scratchpadAPI,
                    cache: environment.container.cacheClient,
                    scratchpadStore: environment.scratchpadStore
                )
                .presentationCompactAdaptation(.sheet)
            }

            SettingsAvatarButton(size: avatarSize)
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event,
                  event.action == .openScratchpad,
                  scratchpadPresentationStyle == .anchoredPopover else { return }
            isScratchpadPresented = true
        }
    }

    private var scratchpadPresentationStyle: ScratchpadPresentationStyle {
        WorkspaceBehaviorPolicy.scratchpadPresentationStyle(isPhoneIdiom: isPhoneIdiom)
    }

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    private func handleScratchpadTap() {
        switch scratchpadPresentationStyle {
        case .anchoredPopover:
            isScratchpadPresented = true
        case .sheet:
            environment.emitShortcutAction(.openScratchpad)
        }
    }
}

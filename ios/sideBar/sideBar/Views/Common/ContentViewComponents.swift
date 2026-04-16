import SwiftUI
import sideBarShared

struct PhoneDetailRoute: Identifiable, Hashable {
    let id: String
}

struct SectionDefinition {
    let section: AppSection
    let panelView: () -> AnyView
    let detailView: () -> AnyView
    let phoneSelection: () -> Binding<PhoneDetailRoute?>
}

public struct ConfigErrorView: View {
    public let error: EnvironmentConfigLoadError

    public init(error: EnvironmentConfigLoadError) {
        self.error = error
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Configuration Error")
                .appFont(.title2)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Check your SideBar.local.xcconfig values and rebuild.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Spacing.xl)
    }
}

enum ActiveAlert: Identifiable, Equatable {
    case biometricUnavailable
    case biometricHint
    case fileReady(ReadyFileNotification)

    var id: String {
        switch self {
        case .biometricUnavailable:
            return "biometricUnavailable"
        case .biometricHint:
            return "biometricHint"
        case .fileReady(let notification):
            return "fileReady-\(notification.id)"
        }
    }
}

struct SignedInContentView<Main: View>: View {
    let showsTopSafeAreaOverlay: Bool
    let topSafeAreaBackground: Color
    let onSignOut: () -> Void
    let onOpenSettings: () -> Void
    let mainView: () -> Main
    let scenePhase: ScenePhase
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if environment.isBiometricUnlockRequired {
                BiometricLockView(
                    onUnlock: {
                        Task {
                            await environment.completeBiometricUnlock()
                        }
                    },
                    onOpenSettings: onOpenSettings,
                    onSignOut: onSignOut,
                    scenePhase: scenePhase
                )
            } else {
                GeometryReader { proxy in
                    mainView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(DesignTokens.Colors.background)
                        .coordinateSpace(name: "appRoot")
                        .overlay(alignment: .top) {
                            if showsTopSafeAreaOverlay {
                                Rectangle()
                                    .fill(topSafeAreaBackground)
                                    .frame(height: proxy.safeAreaInsets.top)
                                    .ignoresSafeArea(edges: .top)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
    }
}

struct StaleAuthRetryBanner: View {
    let isRefreshing: Bool
    let onRetry: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var bannerMaxWidth: CGFloat {
        horizontalSizeClass == .compact ? 360 : 400
    }

    var body: some View {
        GlassEffectContainer(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xsPlus) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "arrow.trianglehead.clockwise.icloud")
                            .appFont(.captionSemibold)
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .leading)
                        Text("Sync paused")
                            .appFont(.labelMd)
                            .lineLimit(1)
                    }
                    Text("Changes may be delayed until session refreshes.")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DesignTokens.Spacing.sm)

                Button {
                    onRetry()
                } label: {
                    retryLabel
                    .frame(minWidth: 54, minHeight: 28)
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .modifier(StaleAuthRetryButtonChromeModifier())
            }
            .padding(.leading, DesignTokens.Spacing.md)
            .padding(.trailing, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(maxWidth: bannerMaxWidth)
            .modifier(StaleAuthRetryBannerChromeModifier())
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var retryLabel: some View {
        if isRefreshing {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("Retry")
                .appFont(.captionSemibold)
        }
    }
}

private struct StaleAuthRetryBannerChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

private struct StaleAuthRetryButtonChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

public struct WelcomeEmptyView: View {
    public init() {
    }

    public var body: some View {
        VStack(spacing: 12) {
            LoadingIndicatorView(size: 96, variant: .hero)
            Text("Welcome to sideBar")
                .appFont(.title3Semibold)
            Text("Select a note, website, or file to get started.")
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct PlaceholderView: View {
    public let title: String
    public let subtitle: String?
    public let actionTitle: String?
    public let action: (() -> Void)?
    public let iconName: String?

    public init(
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        iconName: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.iconName = iconName
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let iconName {
                Image(systemName: iconName)
                    .appFont(.size32Semibold)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .appFont(.title2)
            if let subtitle {
                Text(subtitle)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

enum DetailOfflineUnavailableResource: Equatable {
    case note
    case website
    case file
    case chat

    var title: String {
        switch self {
        case .note:
            return "This note isn't available offline yet"
        case .website:
            return "This website isn't available offline yet"
        case .file:
            return "This file isn't available offline yet"
        case .chat:
            return "This chat isn't available offline yet"
        }
    }

    var subtitle: String {
        "Open it while online on this device to keep it available here."
    }

    var iconName: String {
        switch self {
        case .note:
            return "note.text"
        case .website:
            return "globe"
        case .file:
            return "doc"
        case .chat:
            return "bubble.left.and.bubble.right"
        }
    }
}

struct DetailOfflineUnavailablePlaceholder: View {
    let resource: DetailOfflineUnavailableResource

    var body: some View {
        PlaceholderView(
            title: resource.title,
            subtitle: resource.subtitle,
            iconName: resource.iconName
        )
    }
}

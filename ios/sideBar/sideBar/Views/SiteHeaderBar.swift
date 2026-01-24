import SwiftUI
import Combine

// MARK: - SiteHeaderBar

public struct SiteHeaderBar: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @AppStorage(AppStorageKeys.weatherUsesFahrenheit) private var weatherUsesFahrenheit = false
    @State private var isScratchpadPresented = false
    @State private var isIngestionCenterPresented = false
    private let onSwapContent: (() -> Void)?
    private let onToggleSidebar: (() -> Void)?
    private let onShowSettings: (() -> Void)?
    private let isLeftPanelExpanded: Bool
    private let shouldAnimateSidebar: Bool

    public init(
        onSwapContent: (() -> Void)? = nil,
        onToggleSidebar: (() -> Void)? = nil,
        onShowSettings: (() -> Void)? = nil,
        isLeftPanelExpanded: Bool = true,
        shouldAnimateSidebar: Bool = true
    ) {
        self.onSwapContent = onSwapContent
        self.onToggleSidebar = onToggleSidebar
        self.onShowSettings = onShowSettings
        self.isLeftPanelExpanded = isLeftPanelExpanded
        self.shouldAnimateSidebar = shouldAnimateSidebar
    }

    public var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        brandView
                        Spacer()
                        trailingControls
                    }
                }
            } else {
                HStack(spacing: 16) {
                    brandView
                    Spacer()
                    trailingControls
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .frame(minHeight: LayoutMetrics.appHeaderMinHeight)
        .background(barBackground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        #if os(iOS)
        .onReceive(environment.$shortcutActionEvent) { event in
            guard let event, event.action == .openScratchpad, !isCompact else { return }
            isScratchpadPresented = true
        }
        #endif
    }

    private var brandView: some View {
        HStack(spacing: 10) {
            if isCompact || isLeftPanelExpanded {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .transition(.scale.combined(with: .opacity))
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 4, height: 35)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .opacity(0.9)
                    .transition(.scale.combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("sideBar")
                    .font(DesignTokens.Typography.headlineBold)
                Text("WORKSPACE")
                    .font(DesignTokens.Typography.caption2Semibold)
                    .foregroundStyle(.secondary)
            }
            if shouldShowIngestionStatus {
                Button {
                    isIngestionCenterPresented = true
                } label: {
                    HStack(spacing: 6) {
                        if !environment.ingestionViewModel.activeUploadItems.isEmpty {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else if environment.ingestionViewModel.lastReadyMessage != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Text(ingestionStatusText)
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(.secondary)
                    }
                    .pillStyle()
                }
                .buttonStyle(.plain)
                .padding(.leading, DesignTokens.Spacing.xxsPlus)
                .accessibilityLabel("Show uploads")
                #if os(macOS)
                .popover(isPresented: $isIngestionCenterPresented, arrowEdge: .top) {
                    IngestionCenterView(
                        activeItems: environment.ingestionViewModel.activeUploadItems,
                        failedItems: environment.ingestionViewModel.failedUploadItems,
                        onCancel: { environment.ingestionViewModel.cancelUpload(fileId: $0.file.id) }
                    )
                }
                #else
                .sheet(isPresented: $isIngestionCenterPresented) {
                    IngestionCenterView(
                        activeItems: environment.ingestionViewModel.activeUploadItems,
                        failedItems: environment.ingestionViewModel.failedUploadItems,
                        onCancel: { environment.ingestionViewModel.cancelUpload(fileId: $0.file.id) }
                    )
                }
                #endif
            }
        }
        .animation(shouldAnimateSidebar ? .smooth(duration: 0.3) : nil, value: isLeftPanelExpanded)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCompact {
                onToggleSidebar?()
            }
        }
        .accessibilityLabel(isCompact ? "Show sidebar" : "sideBar")
        .accessibilityAddTraits(isCompact ? .isButton : [])
    }

    private var trailingControls: some View {
        HStack(alignment: .center, spacing: 12) {
            if !isCompact {
                VStack(alignment: .trailing, spacing: 4) {
                    HeaderInfoItem(icon: "cloud.sun", text: weatherText)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(locationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.trailing, DesignTokens.Spacing.smPlus)

                Button(
                    action: { onSwapContent?() },
                    label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .frame(width: 28, height: 28)
                    }
                )
                .buttonStyle(.plain)
                .disabled(onSwapContent == nil)
                .accessibilityLabel("Swap panels")
                .font(DesignTokens.Typography.titleMd)
                .imageScale(.medium)
                .padding(DesignTokens.Spacing.xxsPlus)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(buttonBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(buttonBorder, lineWidth: 1)
                )
            }

            if isCompact {
                Button {
                    onShowSettings?()
                } label: {
                    ProfileAvatarView(size: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .imageScale(.medium)
                .padding(DesignTokens.Spacing.xxsPlus)
                .background(
                    Circle()
                        .fill(buttonBackground)
                )
                .overlay(
                    Circle()
                        .stroke(buttonBorder, lineWidth: 1)
                )
            } else {
                Button {
                    isScratchpadPresented.toggle()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scratchpad")
                .font(DesignTokens.Typography.titleMd)
                .imageScale(.medium)
                .padding(DesignTokens.Spacing.xxsPlus)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(buttonBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(buttonBorder, lineWidth: 1)
                )
                .popover(isPresented: $isScratchpadPresented) {
                    ScratchpadPopoverView(
                        api: environment.container.scratchpadAPI,
                        cache: environment.container.cacheClient,
                        scratchpadStore: environment.scratchpadStore
                    )
                    .frame(minWidth: 360, minHeight: 280)
                }
            }
        }
    }

    private var barBackground: Color {
        DesignTokens.Colors.background
    }

    private var buttonBackground: Color {
        DesignTokens.Colors.surface
    }

    private var buttonBorder: Color {
        DesignTokens.Colors.border
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var weatherText: String {
        if environment.weatherViewModel.isLoading {
            return "Loading..."
        }
        if let weather = environment.weatherViewModel.weather {
            return temperatureText(weather.temperatureC)
        }
        return "Weather"
    }

    private var locationText: String {
        let location = environment.settingsViewModel.settings?.location?.trimmed ?? ""
        return location.isEmpty ? "Set location" : formattedLocation(location)
    }

    private func temperatureText(_ celsius: Double) -> String {
        if weatherUsesFahrenheit {
            let fahrenheit = Int(round(celsius * 9 / 5 + 32))
            return "\(fahrenheit)°F"
        }
        let roundedCelsius = Int(round(celsius))
        return "\(roundedCelsius)°C"
    }

    private func formattedLocation(_ value: String) -> String {
        let parts = value
            .split(separator: ",")
            .map { $0.trimmed }
        guard let first = parts.first else { return value }
        guard let last = parts.last, last != first else { return String(first) }
        let locale = Locale.current
        let city = first.uppercased(with: locale)
        let country = last.uppercased(with: locale)
        return "\(city), \(country)"
    }

    private var shouldShowIngestionStatus: Bool {
        !environment.ingestionViewModel.activeUploadItems.isEmpty ||
            !environment.ingestionViewModel.failedUploadItems.isEmpty ||
            environment.ingestionViewModel.lastReadyMessage != nil
    }

    private var ingestionStatusText: String {
        let activeItems = environment.ingestionViewModel.activeUploadItems
        if let label = activeItems
            .map({ ingestionStatusLabel(for: $0.job) ?? "Processing" })
            .first(where: { $0 != "Processing" }) {
            return label
        }
        if !activeItems.isEmpty {
            return "Processing"
        }
        let failedCount = environment.ingestionViewModel.failedUploadItems.count
        if failedCount > 0 {
            return failedCount == 1 ? "1 Failed" : "\(failedCount) Failed"
        }
        if environment.ingestionViewModel.lastReadyMessage != nil {
            return "Ready"
        }
        return ""
    }
}

private struct HeaderInfoItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
    }
}

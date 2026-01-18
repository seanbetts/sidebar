import SwiftUI

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

    public init(
        onSwapContent: (() -> Void)? = nil,
        onToggleSidebar: (() -> Void)? = nil,
        onShowSettings: (() -> Void)? = nil,
        isLeftPanelExpanded: Bool = true
    ) {
        self.onSwapContent = onSwapContent
        self.onToggleSidebar = onToggleSidebar
        self.onShowSettings = onShowSettings
        self.isLeftPanelExpanded = isLeftPanelExpanded
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: LayoutMetrics.appHeaderMinHeight)
        .background(barBackground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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
                    .font(.headline.weight(.bold))
                Text("WORKSPACE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if shouldShowIngestionStatus {
                Button {
                    isIngestionCenterPresented = true
                } label: {
                    HStack(spacing: 6) {
                        if environment.ingestionViewModel.activeUploadItems.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        Text(ingestionStatusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .pillStyle()
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
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
        .animation(.smooth(duration: 0.3), value: isLeftPanelExpanded)
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
                .padding(.trailing, 14)

                Button(action: { onSwapContent?() }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(onSwapContent == nil)
                .accessibilityLabel("Swap panels")
                .font(.system(size: 16, weight: .semibold))
                .imageScale(.medium)
                .padding(6)
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
                .padding(6)
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
                .font(.system(size: 16, weight: .semibold))
                .imageScale(.medium)
                .padding(6)
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
            let f = Int(round(celsius * 9 / 5 + 32))
            return "\(f)°F"
        }
        let c = Int(round(celsius))
        return "\(c)°C"
    }

    private func formattedLocation(_ value: String) -> String {
        let parts = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let first = parts.first else { return value }
        guard let last = parts.last, last != first else { return String(first) }
        let locale = Locale.current
        let city = first.uppercased(with: locale)
        let country = last.uppercased(with: locale)
        return "\(city), \(country)"
    }

    private var shouldShowIngestionStatus: Bool {
        !environment.ingestionViewModel.activeUploadItems.isEmpty ||
            !environment.ingestionViewModel.failedUploadItems.isEmpty
    }

    private var ingestionStatusText: String {
        let activeCount = environment.ingestionViewModel.activeUploadItems.count
        if activeCount > 0 {
            return activeCount == 1 ? "1 Upload" : "\(activeCount) Uploads"
        }
        let failedCount = environment.ingestionViewModel.failedUploadItems.count
        return failedCount == 1 ? "1 Failed" : "\(failedCount) Failed"
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

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

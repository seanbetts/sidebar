import SwiftUI

public struct SiteHeaderBar: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var isScratchpadPresented = false
    private let onSwapContent: (() -> Void)?
    private let onToggleSidebar: (() -> Void)?
    private let onShowSettings: (() -> Void)?

    public init(
        onSwapContent: (() -> Void)? = nil,
        onToggleSidebar: (() -> Void)? = nil,
        onShowSettings: (() -> Void)? = nil
    ) {
        self.onSwapContent = onSwapContent
        self.onToggleSidebar = onToggleSidebar
        self.onShowSettings = onShowSettings
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
        .background(barBackground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var brandView: some View {
        HStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            Rectangle()
                .fill(Color.primary)
                .frame(width: 4, height: 35)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .opacity(0.9)
            VStack(alignment: .leading, spacing: 2) {
                Text("sideBar")
                    .font(.headline.weight(.bold))
                Text("WORKSPACE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isCompact {
                onToggleSidebar?()
            }
        }
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
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
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
                        cache: environment.container.cacheClient
                    )
                    .frame(minWidth: 360, minHeight: 280)
                }
            }
        }
    }

    private var barBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }


    private var buttonBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var buttonBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
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

import SwiftUI

public struct SiteHeaderBar: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var isScratchpadPresented = false

    public init() {
    }

    public var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        brandView
                        Spacer()
                        controlRow
                    }
                    infoRow
                }
            } else {
                HStack(spacing: 16) {
                    brandView
                    Spacer()
                    infoRow
                    Spacer()
                    controlRow
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(barBackground)
    }

    private var brandView: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 16, weight: .semibold))
            Text("sideBar")
                .font(.headline)
        }
    }

    private var infoRow: some View {
        HStack(spacing: 12) {
            ClockView()
            Divider()
            HeaderInfoItem(icon: "mappin.and.ellipse", text: "Location")
            HeaderInfoItem(icon: "cloud.sun", text: "Weather")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            if !isCompact {
                Button(action: {}) {
                    Image(systemName: "rectangle.split.3x1")
                }
                .buttonStyle(.plain)
            }

            Button {
                isScratchpadPresented.toggle()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isScratchpadPresented) {
                ScratchpadPopoverView(
                    api: environment.container.scratchpadAPI,
                    cache: environment.container.cacheClient
                )
                .frame(minWidth: 360, minHeight: 280)
            }

            Menu {
                Picker("Theme", selection: $environment.themeManager.mode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled")
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

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}

private struct ClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(context.date, format: .dateTime.weekday(.abbreviated).hour().minute())
        }
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

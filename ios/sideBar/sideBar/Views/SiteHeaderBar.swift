import SwiftUI

public struct SiteHeaderBar: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var isScratchpadPresented = false
    private let onTogglePanel: (() -> Void)?
    private let onSwapContent: (() -> Void)?

    public init(onTogglePanel: (() -> Void)? = nil, onSwapContent: (() -> Void)? = nil) {
        self.onTogglePanel = onTogglePanel
        self.onSwapContent = onSwapContent
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var brandView: some View {
        HStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            Text("sideBar")
                .font(.headline)
        }
    }

    private var infoRow: some View {
        HStack(spacing: 12) {
            HeaderInfoItem(icon: "mappin.and.ellipse", text: "Location")
            HeaderInfoItem(icon: "cloud.sun", text: "Weather")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button(action: { onTogglePanel?() }) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .disabled(onTogglePanel == nil)

            Button(action: { onSwapContent?() }) {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.plain)
            .disabled(onSwapContent == nil)

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

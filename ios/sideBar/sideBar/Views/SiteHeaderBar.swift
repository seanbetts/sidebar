import SwiftUI

public struct SiteHeaderBar: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var isScratchpadPresented = false
    private let onSwapContent: (() -> Void)?

    public init(onSwapContent: (() -> Void)? = nil) {
        self.onSwapContent = onSwapContent
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
        HStack(spacing: 8) {
            Image(colorScheme == .dark ? "AppLogoDark" : "AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            Text("sideBar")
                .font(.headline)
        }
    }

    private var trailingControls: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .trailing, spacing: 4) {
                HeaderInfoItem(icon: "cloud.sun", text: "Weather")
                    .fontWeight(.semibold)
                HeaderInfoItem(icon: "mappin.and.ellipse", text: "Location")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
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

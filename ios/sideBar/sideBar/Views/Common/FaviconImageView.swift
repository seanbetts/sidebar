import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct FaviconImageView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    let faviconUrl: String?
    let faviconR2Key: String?
    let r2Endpoint: URL?
    let r2FaviconBucket: String?
    let r2FaviconPublicBaseUrl: URL?
    let size: CGFloat
    @State private var cachedImage: Image?
    @State private var currentUrlString: String?

    private var resolvedUrl: URL? {
        if let key = faviconR2Key, !key.isEmpty {
            if let publicBase = r2FaviconPublicBaseUrl {
                return publicBase.appendingPathComponent(key)
            }
            if let base = r2Endpoint {
                var url = base
                if let bucket = r2FaviconBucket, !bucket.isEmpty {
                    url = url.appendingPathComponent(bucket)
                }
                return url.appendingPathComponent(key)
            }
        }
        if let faviconUrl, let url = URL(string: faviconUrl) {
            return url
        }
        return nil
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(FaviconChipStyle.backgroundColor(for: colorScheme))

            Group {
                if let cachedImage {
                    cachedImage
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholderIcon
                }
            }
            .frame(
                width: FaviconChipStyle.iconSize(for: size),
                height: FaviconChipStyle.iconSize(for: size)
            )
        }
        .overlay(
            Circle()
                .strokeBorder(FaviconChipStyle.borderColor(for: colorScheme), lineWidth: 1)
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: resolvedUrl?.absoluteString) {
            await loadImage(for: resolvedUrl)
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "globe")
            .font(.system(size: FaviconChipStyle.placeholderFontSize(for: size)))
            .foregroundStyle(.secondary)
    }

    @MainActor
    private func loadImage(for url: URL?) async {
        guard let url else {
            cachedImage = nil
            currentUrlString = nil
            return
        }

        let urlString = url.absoluteString
        guard currentUrlString != urlString else { return }
        currentUrlString = urlString

        if let cachedData: Data = environment.container.cacheClient.get(
            key: CacheKeys.favicon(url: urlString)
        ) {
            cachedImage = loadImage(from: cachedData)
            return
        }

        if environment.isOffline || !environment.isNetworkAvailable {
            cachedImage = nil
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                cachedImage = nil
                return
            }
            guard let image = loadImage(from: data) else {
                cachedImage = nil
                return
            }
            cachedImage = image
            environment.container.cacheClient.set(
                key: CacheKeys.favicon(url: urlString),
                value: data,
                ttlSeconds: CachePolicy.faviconImage
            )
        } catch {
            cachedImage = nil
        }
    }

    private func loadImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}

private enum FaviconChipStyle {
    static func iconSize(for size: CGFloat) -> CGFloat {
        max(8, size * 0.78)
    }

    static func placeholderFontSize(for size: CGFloat) -> CGFloat {
        max(6, size * 0.58)
    }

    static func backgroundColor(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.06)
        }
    }

    static func borderColor(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.22)
        default:
            return Color.black.opacity(0.12)
        }
    }
}

import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct FaviconImageView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let faviconUrl: String?
    let faviconR2Key: String?
    let r2Endpoint: URL?
    let r2FaviconBucket: String?
    let r2FaviconPublicBaseUrl: URL?
    let size: CGFloat
    let placeholderTint: Color
    @State private var cachedImage: Image?
    @State private var currentUrlString: String?

    private var faviconSourceLabel: String {
        if let faviconR2Key, !faviconR2Key.isEmpty {
            return "r2"
        }
        if let faviconUrl, !faviconUrl.isEmpty {
            return "remote"
        }
        return "none"
    }

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
        Group {
            if let cachedImage {
                cachedImage
                    .resizable()
                    .scaledToFit()
            } else {
                placeholderIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: resolvedUrl?.absoluteString) {
            await loadImage(for: resolvedUrl)
        }
    }

    private var placeholderIcon: some View {
        Image(appIcon: AppIcon.Content.websiteFallback)
            .foregroundStyle(placeholderTint)
    }

    @MainActor
    private func loadImage(for url: URL?) async {
        let baseDetails = faviconBaseDetails
        guard let url else {
            cachedImage = nil
            currentUrlString = nil
            WebsiteQueueDebugTrace.log(
                "favicon.load.reset",
                details: baseDetails
            )
            return
        }

        let urlString = url.absoluteString
        let urlDetails = baseDetails + [
            "host=\(url.host ?? "unknown")"
        ]
        guard currentUrlString != urlString else {
            WebsiteQueueDebugTrace.log(
                "favicon.load.skip-duplicate",
                details: urlDetails
            )
            return
        }
        currentUrlString = urlString

        if let cachedData: Data = environment.container.cacheClient.get(
            key: CacheKeys.favicon(url: urlString)
        ) {
            showCachedImage(cachedData, details: urlDetails)
            return
        }

        if environment.isOffline || !environment.isNetworkAvailable {
            clearImageAndLog("favicon.load.skipped-offline", details: urlDetails)
            return
        }

        await loadRemoteImage(for: url, urlString: urlString, details: urlDetails)
    }

    private var faviconBaseDetails: [String] {
        [
            "source=\(faviconSourceLabel)",
            "size=\(Int(size))"
        ]
    }

    @MainActor
    private func showCachedImage(_ data: Data, details: [String]) {
        cachedImage = loadImage(from: data)
        WebsiteQueueDebugTrace.log(
            "favicon.load.cache-hit",
            details: details + [
                "bytes=\(data.count)"
            ]
        )
    }

    @MainActor
    private func clearImageAndLog(_ event: String, details: [String]) {
        cachedImage = nil
        WebsiteQueueDebugTrace.log(event, details: details)
    }

    @MainActor
    private func loadRemoteImage(for url: URL, urlString: String, details: [String]) async {
        do {
            let start = ProcessInfo.processInfo.systemUptime
            WebsiteQueueDebugTrace.log(
                "favicon.load.network.start",
                details: details
            )
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
                clearImageAndLog(
                    "favicon.load.network.bad-status",
                    details: details + [
                        "status_code=\(statusCode)",
                        "elapsed_ms=\(elapsedMs)"
                    ]
                )
                return
            }
            guard let image = loadImage(from: data) else {
                let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
                clearImageAndLog(
                    "favicon.load.network.invalid-image",
                    details: details + [
                        "bytes=\(data.count)",
                        "elapsed_ms=\(elapsedMs)"
                    ]
                )
                return
            }
            cachedImage = image
            environment.container.cacheClient.set(
                key: CacheKeys.favicon(url: urlString),
                value: data,
                ttlSeconds: CachePolicy.faviconImage
            )
            let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
            WebsiteQueueDebugTrace.log(
                "favicon.load.network.success",
                details: details + [
                    "bytes=\(data.count)",
                    "elapsed_ms=\(elapsedMs)"
                ]
            )
        } catch {
            clearImageAndLog(
                "favicon.load.network.error",
                details: details + [
                    "error=\(error.localizedDescription)"
                ]
            )
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

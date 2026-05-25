import Combine
import Foundation
import sideBarShared
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum CachedMarkdownRemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

@MainActor
final class CachedMarkdownRemoteImageLoader: ObservableObject {
    #if os(iOS)
    private typealias PlatformImage = UIImage
    #elseif os(macOS)
    private typealias PlatformImage = NSImage
    #endif

    private static let imageCache = NSCache<NSURL, PlatformImage>()
    @Published private(set) var phase: CachedMarkdownRemoteImagePhase = .empty
    private var currentURL: URL?
    private let session: URLSession
    private let maxImageDataBytes: Int64

    init(session: URLSession = .shared, maxImageDataBytes: Int64 = 5_000_000) {
        self.session = session
        self.maxImageDataBytes = maxImageDataBytes
    }

    func load(url: URL?) async {
        guard let url else {
            currentURL = nil
            phase = .empty
            return
        }
        guard currentURL != url else {
            return
        }
        currentURL = url
        phase = .empty

        if let cached = Self.imageCache.object(forKey: url as NSURL) {
            phase = .success(Self.makeImage(from: cached))
            return
        }

        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            phase = .failure
            return
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        do {
            let (temporaryURL, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard currentURL == url else { return }
            guard let data = try validatedImageData(at: temporaryURL, response: response) else {
                return failCurrentURL(url)
            }
            guard let platformImage = Self.makePlatformImage(from: data) else {
                return failCurrentURL(url)
            }
            Self.imageCache.setObject(platformImage, forKey: url as NSURL)
            phase = .success(Self.makeImage(from: platformImage))
        } catch {
            guard currentURL == url else { return }
            phase = .failure
        }
    }

    private func validatedImageData(at temporaryURL: URL, response: URLResponse) throws -> Data? {
        guard Self.isSupportedImageResponse(response),
              response.expectedContentLength <= maxImageDataBytes else {
            return nil
        }
        let fileSize = try Self.fileSize(at: temporaryURL)
        guard fileSize <= maxImageDataBytes else {
            return nil
        }
        return try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
    }

    private func failCurrentURL(_ url: URL) {
        guard currentURL == url else { return }
        phase = .failure
    }

    private static func isSupportedImageResponse(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else {
            return true
        }
        return (200..<300).contains(http.statusCode) && http.isImageResponse
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func makePlatformImage(from data: Data) -> PlatformImage? {
        #if os(iOS)
        return UIImage(data: data)
        #elseif os(macOS)
        return NSImage(data: data)
        #endif
    }

    private static func makeImage(from image: PlatformImage) -> Image {
        #if os(iOS)
        return Image(uiImage: image)
        #elseif os(macOS)
        return Image(nsImage: image)
        #endif
    }
}

private extension HTTPURLResponse {
    var isImageResponse: Bool {
        guard let mimeType = mimeType?.lowercased() else {
            return true
        }
        return mimeType.hasPrefix("image/")
    }
}

struct CachedMarkdownRemoteImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (CachedMarkdownRemoteImagePhase) -> Content

    @StateObject private var loader = CachedMarkdownRemoteImageLoader()

    var body: some View {
        content(loader.phase)
            .task(id: url?.absoluteString) {
                await loader.load(url: url)
            }
    }
}

struct MarkdownGalleryView: View {
    let gallery: MarkdownRendering.MarkdownGallery

    private let gridSpacing: CGFloat = SideBarMarkdownLayout.gallerySpacing
    private let minImageWidth: CGFloat = SideBarMarkdownLayout.galleryMinImageWidth

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(
                minimum: minImageWidth,
                maximum: SideBarMarkdownLayout.maxImageSize.width
            ),
            spacing: gridSpacing
        )]
    }

    var body: some View {
        VStack(alignment: .center, spacing: gridSpacing) {
            LazyVGrid(columns: columns, alignment: .center, spacing: gridSpacing) {
                ForEach(gallery.imageUrls, id: \.self) { urlString in
                    MarkdownGalleryImageView(
                        urlString: urlString,
                        maxSize: CGSize(
                            width: SideBarMarkdownLayout.maxImageSize.width,
                            height: SideBarMarkdownLayout.maxImageSize.height
                        )
                    )
                }
            }
            if let caption = gallery.caption, !caption.isEmpty {
                Text(caption)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MarkdownGalleryImageView: View {
    let urlString: String
    let maxSize: CGSize

    var body: some View {
        if let url = URL(string: urlString) {
            CachedMarkdownRemoteImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
                case .failure:
                    Image(appIcon: AppIcon.Content.photo)
                        .appFont(.displayLg)
                        .foregroundStyle(.secondary)
                case .empty:
                    LoadingIndicatorView(size: LoadingIndicatorSize.control)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

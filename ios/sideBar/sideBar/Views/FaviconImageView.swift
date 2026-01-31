import SwiftUI

struct FaviconImageView: View {
    let faviconUrl: String?
    let faviconR2Key: String?
    let r2Endpoint: URL?
    let r2FaviconBucket: String?
    let r2FaviconPublicBaseUrl: URL?
    let size: CGFloat
    let placeholderTint: Color

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
        if let url = resolvedUrl {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    placeholderIcon
                }
            }
            .frame(width: size, height: size)
        } else {
            placeholderIcon
                .frame(width: size, height: size)
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "globe")
            .foregroundStyle(placeholderTint)
    }
}

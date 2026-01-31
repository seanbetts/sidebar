import SwiftUI

struct FaviconImageView: View {
    let faviconUrl: String?
    let faviconR2Key: String?
    let r2PublicBaseUrl: URL?
    let size: CGFloat
    let placeholderTint: Color

    private var resolvedUrl: URL? {
        if let base = r2PublicBaseUrl, let key = faviconR2Key, !key.isEmpty {
            return base.appendingPathComponent(key)
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

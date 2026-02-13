import SwiftUI

struct WidgetWebsiteFaviconView: View {
    let site: WidgetWebsite
    let size: CGFloat

    var body: some View {
        Group {
            if let faviconURL = site.resolvedFaviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "globe")
            .font(.system(size: max(6, size * 0.8)))
            .foregroundStyle(.secondary)
    }
}

extension WidgetWebsite {
    var resolvedFaviconURL: URL? {
        if let faviconUrl, let metadataURL = URL(string: faviconUrl),
           ["http", "https"].contains(metadataURL.scheme?.lowercased() ?? "") {
            return metadataURL
        }

        guard let siteURL = URL(string: url),
              let scheme = siteURL.scheme,
              let host = siteURL.host,
              ["http", "https"].contains(scheme.lowercased()) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/favicon.ico"
        return components.url
    }
}

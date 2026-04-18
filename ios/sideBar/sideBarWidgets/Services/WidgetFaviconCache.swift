import Foundation
import sideBarShared

enum WidgetFaviconCache {
    private static let directoryName = "WidgetFavicons"
    private static let maxCachedBytes = 512_000

    static func load(for websites: [WidgetWebsite]) -> [String: Data] {
        guard let cacheDirectory else { return [:] }

        var cached: [String: Data] = [:]
        for website in websites {
            let fileURL = cacheDirectory.appendingPathComponent(cacheFileName(for: website.id))
            guard let data = try? Data(contentsOf: fileURL),
                  !data.isEmpty,
                  data.count <= maxCachedBytes else {
                continue
            }
            cached[website.id] = data
        }
        return cached
    }

    static func store(_ faviconDataByWebsiteId: [String: Data]) {
        guard !faviconDataByWebsiteId.isEmpty,
              let cacheDirectory else { return }

        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        for (websiteId, data) in faviconDataByWebsiteId where !data.isEmpty && data.count <= maxCachedBytes {
            let fileURL = cacheDirectory.appendingPathComponent(cacheFileName(for: websiteId))
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    private static var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func cacheFileName(for websiteId: String) -> String {
        let encoded = Data(websiteId.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return "\(encoded).bin"
    }
}

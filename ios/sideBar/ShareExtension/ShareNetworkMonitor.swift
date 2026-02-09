import Foundation
import sideBarShared

enum ShareNetworkMonitor {
    static func isOnline(
        timeout: TimeInterval = 0.3,
        probeURLs: [URL]? = nil,
        session: URLSession = APIClient.makeDefaultSession()
    ) async -> Bool {
        let targets = probeURLs ?? defaultProbeURLs()
        guard !targets.isEmpty else { return true }
        for url in targets where await probe(url: url, timeout: timeout, session: session) {
            return true
        }
        return false
    }

    private static func probe(url: URL, timeout: TimeInterval, session: URLSession) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...399).contains(http.statusCode) {
                    return true
                }
                if http.statusCode != 405 {
                    return false
                }
            }
            return true
        } catch {
            return await probeWithGet(url: url, timeout: timeout, session: session)
        }
    }

    private static func probeWithGet(url: URL, timeout: TimeInterval, session: URLSession) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return true }
            return (200...399).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private static func defaultProbeURLs() -> [URL] {
        var urls: [URL] = []
        if let apiProbeURL = apiHealthProbeURL() {
            urls.append(apiProbeURL)
        }
        if let googleProbe = URL(string: "https://www.gstatic.com/generate_204") {
            urls.append(googleProbe)
        }
        if let appleProbe = URL(string: "https://www.apple.com/library/test/success.html") {
            urls.append(appleProbe)
        }
        return unique(urls)
    }

    private static func apiHealthProbeURL() -> URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           let baseURL = URL(string: normalized) {
            return baseURL.appendingPathComponent("health")
        }
        return URL(string: "https://sidebar-api.fly.dev/api/v1/health")
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

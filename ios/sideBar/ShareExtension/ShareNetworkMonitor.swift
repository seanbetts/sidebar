import Foundation

enum ShareNetworkMonitor {
    static func isOnline(timeout: TimeInterval = 0.3) async -> Bool {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else {
            return true
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch {
            return false
        }
    }
}

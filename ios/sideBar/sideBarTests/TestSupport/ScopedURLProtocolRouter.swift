import Foundation

final class ScopedURLProtocolRouter {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    let baseURL: URL

    private let routerID: String

    init() {
        routerID = UUID().uuidString
        baseURL = URL(string: "https://scoped-url-protocol.invalid/\(routerID)")!
        ScopedURLProtocol.registerRouter(id: routerID)
    }

    func setHandler(_ handler: @escaping Handler) {
        ScopedURLProtocol.setHandler(handler, for: routerID)
    }

    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScopedURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    func invalidate() {
        ScopedURLProtocol.unregisterRouter(id: routerID)
    }
}

private final class ScopedURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: ScopedURLProtocolRouter.Handler] = [:]

        func registerRouter(id: String) {
            lock.lock()
            handlers[id] = nil
            lock.unlock()
        }

        func setHandler(_ handler: @escaping ScopedURLProtocolRouter.Handler, for id: String) {
            lock.lock()
            handlers[id] = handler
            lock.unlock()
        }

        func handler(for id: String) -> ScopedURLProtocolRouter.Handler? {
            lock.lock()
            defer { lock.unlock() }
            return handlers[id]
        }

        func unregisterRouter(id: String) {
            lock.lock()
            handlers.removeValue(forKey: id)
            lock.unlock()
        }
    }

    private static let registry = Registry()
    private static let host = "scoped-url-protocol.invalid"

    static func registerRouter(id: String) {
        registry.registerRouter(id: id)
    }

    static func setHandler(_ handler: @escaping ScopedURLProtocolRouter.Handler, for id: String) {
        registry.setHandler(handler, for: id)
    }

    static func unregisterRouter(id: String) {
        registry.unregisterRouter(id: id)
    }

    // URLProtocol requires class overrides here even in a final subclass.
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let routerID = url.pathComponents.dropFirst().first else {
            client?.urlProtocol(self, didFailWithError: ScopedURLProtocolError.missingRouterID)
            return
        }
        guard let handler = Self.registry.handler(for: routerID) else {
            client?.urlProtocol(self, didFailWithError: ScopedURLProtocolError.missingHandler(routerID))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}

private enum ScopedURLProtocolError: LocalizedError {
    case missingRouterID
    case missingHandler(String)

    var errorDescription: String? {
        switch self {
        case .missingRouterID:
            return "Missing scoped URLProtocol router identifier"
        case .missingHandler(let routerID):
            return "Missing scoped URLProtocol handler for router \(routerID)"
        }
    }
}

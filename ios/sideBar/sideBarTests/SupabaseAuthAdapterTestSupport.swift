import XCTest
import sideBarShared
import Supabase
@testable import sideBar

final class FakeSupabaseAuthClient: SupabaseAuthClientProtocol, @unchecked Sendable {
    var currentSession: SupabaseSessionInfo?
    var signInResult: Result<Void, Error>?
    var refreshResult: Result<SupabaseSessionInfo, Error>?
    var signOutError: Error?
    var updatedPasswords: [String] = []

    private var continuation: AsyncStream<(SupabaseAuthEvent, SupabaseSessionInfo?)>.Continuation?
    private var pendingEvents: [(SupabaseAuthEvent, SupabaseSessionInfo?)] = []
    var hasSubscriber: Bool { continuation != nil }

    var authStateChanges: AsyncStream<(SupabaseAuthEvent, SupabaseSessionInfo?)> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.pendingEvents.forEach { continuation.yield($0) }
            self.pendingEvents.removeAll()
        }
    }

    func yield(event: SupabaseAuthEvent, session: SupabaseSessionInfo?) {
        if let continuation {
            continuation.yield((event, session))
        } else {
            pendingEvents.append((event, session))
        }
    }

    func finish() {
        continuation?.finish()
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        if let signInResult {
            switch signInResult {
            case .success:
                return
            case .failure(let error):
                throw error
            }
        }
    }

    func signUp(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func verifyOTP(email: String, code: String) async throws -> SupabaseSessionInfo {
        _ = email
        _ = code
        throw AuthAdapterError.invalidCredentials
    }

    func session(from url: URL) async throws -> SupabaseSessionInfo {
        _ = url
        throw AuthAdapterError.invalidCredentials
    }

    func updatePassword(_ password: String) async throws {
        updatedPasswords.append(password)
    }

    func refreshSession() async throws -> SupabaseSessionInfo {
        guard let refreshResult else {
            throw NSError(domain: "FakeSupabaseAuthClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No refresh result configured"
            ])
        }
        switch refreshResult {
        case .success(let session):
            currentSession = session
            return session
        case .failure(let error):
            throw error
        }
    }

    func signOut() async throws {
        if let signOutError {
            throw signOutError
        }
        currentSession = nil
    }
}

@MainActor
extension SupabaseAuthAdapterTests {
    func base64UrlEncode(_ payload: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
        let encoded = data?.base64EncodedString() ?? ""
        return encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func makeJwt(exp: TimeInterval) -> String {
        let header = base64UrlEncode(["alg": "none", "typ": "JWT"])
        let payload = base64UrlEncode(["exp": exp, "sub": "user"])
        return "\(header).\(payload)."
    }

    func XCTAssertThrowsErrorAsync(
        _ expression: @escaping () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error to be thrown", file: file, line: line)
        } catch {
        }
    }

    func waitUntil(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
        let timeout = Date().addingTimeInterval(timeoutSeconds)
        while Date() < timeout {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition")
    }

    func drainAuthEventLoop(iterations: Int = 16) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }
}

final class BlockingAuthStateStore: AuthStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private let writeSemaphore = DispatchSemaphore(value: 0)
    private var shouldBlockWrites = false

    private(set) var persistedAccessToken: String?
    private(set) var persistedUserId: String?

    func blockWrites() {
        lock.lock()
        shouldBlockWrites = true
        lock.unlock()
    }

    func releaseWrites() {
        lock.lock()
        let wasBlocking = shouldBlockWrites
        shouldBlockWrites = false
        lock.unlock()
        if wasBlocking {
            writeSemaphore.signal()
            writeSemaphore.signal()
        }
    }

    func saveAccessToken(_ token: String?) throws {
        waitIfNeeded()
        lock.lock()
        persistedAccessToken = token
        lock.unlock()
    }

    func saveUserId(_ userId: String?) throws {
        waitIfNeeded()
        lock.lock()
        persistedUserId = userId
        lock.unlock()
    }

    func loadAccessToken() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return persistedAccessToken
    }

    func loadUserId() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return persistedUserId
    }

    func clear() throws {
        lock.lock()
        persistedAccessToken = nil
        persistedUserId = nil
        lock.unlock()
    }

    private func waitIfNeeded() {
        lock.lock()
        let shouldWait = shouldBlockWrites
        lock.unlock()
        if shouldWait {
            _ = writeSemaphore.wait(timeout: .now() + 5)
        }
    }
}

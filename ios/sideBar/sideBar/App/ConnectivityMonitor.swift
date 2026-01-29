import Combine
import Foundation
import Network
import sideBarShared

@MainActor
final class ConnectivityMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var isOffline: Bool = false
    @Published private(set) var isNetworkAvailable: Bool = true
    @Published private(set) var isServerReachable: Bool = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "sidebar.connectivity.monitor")
    private let baseUrl: URL
    private let internetProbeUrl: URL
    private let session: URLSession
    private var probeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var consecutiveFailures = 0

    init(
        baseUrl: URL,
        startMonitoring: Bool = true,
        session: URLSession = .shared,
        internetProbeUrl: URL = URL(string: "https://www.apple.com/library/test/success.html")!
    ) {
        self.baseUrl = baseUrl
        self.session = session
        self.internetProbeUrl = internetProbeUrl
        self.monitor = NWPathMonitor()
        if startMonitoring {
            monitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor [weak self] in
                    self?.handlePathUpdate(path)
                }
            }
            monitor.start(queue: queue)
        }
        observeRequestFailures()
    }

    deinit {
        monitor.cancel()
        probeTask?.cancel()
    }

    private func handlePathUpdate(_ path: NWPath) {
        let available = path.status == .satisfied
        if !available {
            setStatus(networkAvailable: false, serverReachable: false)
            probeTask?.cancel()
            return
        }
        setStatus(networkAvailable: true, serverReachable: isServerReachable)
        scheduleProbe(immediate: true)
    }

    private func observeRequestFailures() {
        NotificationCenter.default.publisher(for: .apiClientRequestFailed)
            .sink { [weak self] notification in
                self?.handleRequestFailure(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .apiClientRequestSucceeded)
            .sink { [weak self] _ in
                self?.handleRequestSuccess()
            }
            .store(in: &cancellables)
    }

    private func handleRequestFailure(_ notification: Notification) {
        let statusCode = notification.userInfo?["statusCode"] as? Int
        let error = notification.userInfo?["error"] as? Error
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                setStatus(networkAvailable: false, serverReachable: false)
                return
            default:
                break
            }
        }
        if let statusCode, statusCode >= 500 {
            setStatus(networkAvailable: true, serverReachable: false)
        }
        scheduleProbe(immediate: false)
    }

    private func handleRequestSuccess() {
        consecutiveFailures = 0
        setStatus(networkAvailable: true, serverReachable: true)
    }

    private func scheduleProbe(immediate: Bool) {
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                let delay = backoffDelay(for: consecutiveFailures)
                try? await Task.sleep(nanoseconds: delay)
            }
            await self.probeNetworkAndServer()
        }
    }

    private func probeNetworkAndServer() async {
        let networkAvailable = await probeInternet()
        if !networkAvailable {
            setStatus(networkAvailable: false, serverReachable: false)
            return
        }
        let serverReachable = await probeServer()
        if serverReachable {
            consecutiveFailures = 0
            setStatus(networkAvailable: true, serverReachable: true)
            return
        }
        consecutiveFailures += 1
        setStatus(networkAvailable: true, serverReachable: false)
        scheduleProbe(immediate: false)
    }

    private func setStatus(networkAvailable: Bool, serverReachable: Bool) {
        isNetworkAvailable = networkAvailable
        isServerReachable = serverReachable
        isOffline = !networkAvailable || !serverReachable
    }

    private func probeInternet() async -> Bool {
        var request = URLRequest(url: internetProbeUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
        } catch {
            return false
        }
        return false
    }

    private func probeServer() async -> Bool {
        let url = baseUrl.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
        } catch {
            return false
        }
        return false
    }

    private func backoffDelay(for failures: Int) -> UInt64 {
        let attempt = max(failures, 1)
        let seconds = min(pow(2.0, Double(attempt - 1)), 30.0)
        return UInt64(seconds * 1_000_000_000)
    }
}

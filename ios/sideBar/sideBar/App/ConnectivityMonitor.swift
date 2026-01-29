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
    private var schedulerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastProbeAt: Date?
    private var isProbing = false
    private let minimumProbeInterval: TimeInterval = 2
    private let offlineFailureThreshold = 2
    private let onlineSuccessThreshold = 2
    private let offlineProbeInterval: TimeInterval = 5
    private let onlineProbeInterval: TimeInterval = 30
    private var consecutiveInternetFailures = 0
    private var consecutiveInternetSuccesses = 0
    private var consecutiveServerFailures = 0
    private var consecutiveServerSuccesses = 0

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
        startScheduler()
    }

    deinit {
        monitor.cancel()
        probeTask?.cancel()
        schedulerTask?.cancel()
    }

    private func handlePathUpdate(_ path: NWPath) {
        let available = path.status == .satisfied
        if !available {
            resetCounters()
            setStatus(networkAvailable: false, serverReachable: false)
            scheduleProbe(immediate: false)
            return
        }
        resetCounters()
        recordInternetSuccess()
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
                recordInternetFailure()
                recordServerFailure()
                return
            default:
                break
            }
        }
        if let statusCode, statusCode >= 500 {
            recordServerFailure()
        }
        scheduleProbe(immediate: false)
    }

    private func handleRequestSuccess() {
        recordInternetSuccess()
        recordServerSuccess()
    }

    private func scheduleProbe(immediate: Bool) {
        if let lastProbeAt,
           !immediate,
           Date().timeIntervalSince(lastProbeAt) < minimumProbeInterval {
            return
        }
        if isProbing {
            return
        }
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            guard let self else { return }
            self.isProbing = true
            self.lastProbeAt = Date()
            defer { self.isProbing = false }
            if !immediate {
                let delay = probeDelay()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await self.probeNetworkAndServer()
        }
    }

    private func probeNetworkAndServer() async {
        let networkAvailable = await probeInternet()
        if !networkAvailable {
            recordInternetFailure()
            recordServerFailure()
            scheduleProbe(immediate: false)
            return
        }
        recordInternetSuccess()
        let serverReachable = await probeServer()
        if serverReachable {
            recordServerSuccess()
            return
        }
        recordServerFailure()
        scheduleProbe(immediate: false)
    }

    private func setStatus(networkAvailable: Bool, serverReachable: Bool) {
        isNetworkAvailable = networkAvailable
        isServerReachable = serverReachable
        isOffline = !networkAvailable || !serverReachable
    }

    private func recordInternetFailure() {
        consecutiveInternetFailures += 1
        consecutiveInternetSuccesses = 0
        if consecutiveInternetFailures >= offlineFailureThreshold {
            setStatus(networkAvailable: false, serverReachable: false)
        }
    }

    private func recordInternetSuccess() {
        consecutiveInternetSuccesses += 1
        consecutiveInternetFailures = 0
        if consecutiveInternetSuccesses >= onlineSuccessThreshold {
            setStatus(networkAvailable: true, serverReachable: isServerReachable)
        }
    }

    private func recordServerFailure() {
        consecutiveServerFailures += 1
        consecutiveServerSuccesses = 0
        if consecutiveServerFailures >= offlineFailureThreshold {
            setStatus(networkAvailable: isNetworkAvailable, serverReachable: false)
        }
    }

    private func recordServerSuccess() {
        consecutiveServerSuccesses += 1
        consecutiveServerFailures = 0
        if consecutiveServerSuccesses >= onlineSuccessThreshold {
            setStatus(networkAvailable: isNetworkAvailable, serverReachable: true)
        }
    }

    private func resetCounters() {
        consecutiveInternetFailures = 0
        consecutiveInternetSuccesses = 0
        consecutiveServerFailures = 0
        consecutiveServerSuccesses = 0
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

    private func probeDelay() -> TimeInterval {
        if isOffline {
            return offlineProbeInterval
        }
        return onlineProbeInterval
    }

    private func startScheduler() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let delay = probeDelay()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await self.probeNetworkAndServer()
            }
        }
    }
}

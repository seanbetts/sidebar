import Combine
import Foundation
import Network
import sideBarShared

@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOffline: Bool = false
    @Published private(set) var isNetworkAvailable: Bool = true
    @Published private(set) var isServerReachable: Bool = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "sidebar.connectivity.monitor")
    private let baseUrl: URL
    private let internetProbeUrl: URL
    private let session: URLSession
    private let notificationCenter: NotificationCenter
    private let allowsHealthProbes: Bool
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
        startMonitoring: Bool = !EnvironmentConfig.isRunningTestsOrPreviews(),
        session: URLSession = .shared,
        notificationCenter: NotificationCenter = .default,
        internetProbeUrl: URL = URL(string: "https://www.apple.com/library/test/success.html")!
    ) {
        self.baseUrl = baseUrl
        self.session = session
        self.notificationCenter = notificationCenter
        self.internetProbeUrl = internetProbeUrl
        self.allowsHealthProbes = startMonitoring
        self.monitor = NWPathMonitor()
        if startMonitoring {
            monitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor [weak self] in
                    self?.handlePathUpdate(path)
                }
            }
            monitor.start(queue: queue)
            startScheduler()
        }
        observeRequestFailures()
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
        notificationCenter.publisher(for: .apiClientRequestFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleRequestFailure(notification)
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: .apiClientRequestSucceeded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleRequestSuccess(notification)
            }
            .store(in: &cancellables)
    }

    private func handleRequestFailure(_ notification: Notification) {
        if let signal = notification.userInfo?["signal"] as? RequestLifecycleSignal {
            handleLifecycleFailure(signal)
            scheduleProbe(immediate: false)
            return
        }

        let statusCode = notification.userInfo?["statusCode"] as? Int
        let error = notification.userInfo?["error"] as? Error
        if let error,
           let category = URLRequestErrorClassifier.category(for: error) {
            switch category {
            case .offline:
                recordInternetFailure()
                recordServerFailure()
                return
            case .timeout, .serverUnreachable, .secureConnection:
                // Endpoint-specific reachability/TLS failures should mark server status
                // without treating the device as offline.
                recordServerFailure()
                scheduleProbe(immediate: false)
                return
            case .authRequired, .cancelled, .other:
                break
            }
        }

        if let statusCode, statusCode >= 500 {
            recordServerFailure()
        }
        scheduleProbe(immediate: false)
    }

    private func handleRequestSuccess(_ notification: Notification) {
        if let signal = notification.userInfo?["signal"] as? RequestLifecycleSignal,
           signal.stage != .succeeded {
            return
        }
        recordInternetSuccess()
        recordServerSuccess()
    }

    private func handleLifecycleFailure(_ signal: RequestLifecycleSignal) {
        guard signal.stage == .failed, let category = signal.errorCategory else {
            return
        }

        switch category {
        case .offline:
            recordInternetFailure()
            recordServerFailure()
        case .serverBusy, .serverUnreachable, .timeout, .secureConnection:
            recordServerFailure()
        case .authentication,
             .permission,
             .rateLimited,
             .requestRejected,
             .payloadTooLarge,
             .decoding,
             .cancelled,
             .unknown:
            break
        }
    }

    private func scheduleProbe(immediate: Bool) {
        guard allowsHealthProbes else {
            return
        }
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
            self.beginProbe()
            defer { self.endProbe() }
            if !immediate {
                let delay = probeDelay()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await self.probeNetworkAndServer()
        }
    }

    func refreshStatusNow() async {
        guard !isProbing else {
            return
        }
        probeTask?.cancel()
        beginProbe()
        defer { endProbe() }

        let networkAvailable = await probeInternet()
        guard networkAvailable else {
            resetCounters()
            setStatus(networkAvailable: false, serverReachable: false)
            if allowsHealthProbes {
                scheduleProbe(immediate: false)
            }
            return
        }

        let serverReachable = await probeServer()
        resetCounters()
        setStatus(networkAvailable: true, serverReachable: serverReachable)
        if allowsHealthProbes, !serverReachable {
            scheduleProbe(immediate: false)
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
        // Offline reflects device connectivity only; server reachability is tracked separately.
        let isOffline = !networkAvailable
        guard self.isNetworkAvailable != networkAvailable ||
                self.isServerReachable != serverReachable ||
                self.isOffline != isOffline else {
            return
        }
        self.isNetworkAvailable = networkAvailable
        self.isServerReachable = serverReachable
        self.isOffline = isOffline
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
        if !isNetworkAvailable || !isServerReachable {
            return offlineProbeInterval
        }
        return onlineProbeInterval
    }

    private func beginProbe() {
        isProbing = true
        lastProbeAt = Date()
    }

    private func endProbe() {
        isProbing = false
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

extension ConnectivityMonitor {
    var offlineCapabilityPolicyPublisher: AnyPublisher<OfflineCapabilityPolicy, Never> {
        Publishers.CombineLatest3($isOffline, $isNetworkAvailable, $isServerReachable)
            .map { isOffline, isNetworkAvailable, isServerReachable in
                OfflineCapabilityPolicy(
                    isOffline: isOffline,
                    isNetworkAvailable: isNetworkAvailable,
                    isServerReachable: isServerReachable
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

import Foundation
import sideBarShared
import OSLog

// MARK: - IngestionUploadManager

/// Defines the requirements for IngestionUploadManaging.
public protocol IngestionUploadManaging: AnyObject {
    func startUpload(
        request: UploadRequest,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    )
    func cancelUpload(uploadId: String)
}

/// Describes an ingestion upload request and its metadata.
public struct UploadRequest {
    public let uploadId: String
    public let fileURL: URL
    public let filename: String
    public let mimeType: String
    public let folder: String

    public init(uploadId: String, fileURL: URL, filename: String, mimeType: String, folder: String) {
        self.uploadId = uploadId
        self.fileURL = fileURL
        self.filename = filename
        self.mimeType = mimeType
        self.folder = folder
    }
}

/// Handles background uploads for ingestion.
public final class IngestionUploadManager: NSObject, IngestionUploadManaging {
    private let config: APIClientConfig
    private let logger = Logger(subsystem: "sideBar", category: "Upload")
    private let providedSession: URLSession?
    private let certificatePinningDelegate: CertificatePinningDelegate?
    private lazy var session: URLSession = {
        let configuration: URLSessionConfiguration
        if let providedSession {
            configuration = providedSession.configuration
        } else {
            #if os(iOS)
            if EnvironmentConfig.isRunningTestsOrPreviews() {
                configuration = .default
            } else {
                let backgroundConfiguration = URLSessionConfiguration.background(
                    withIdentifier: "sideBar.ingestion.uploads"
                )
                backgroundConfiguration.sessionSendsLaunchEvents = true
                backgroundConfiguration.isDiscretionary = false
                configuration = backgroundConfiguration
            }
            #else
            configuration = .default
            #endif
        }
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private let queue = DispatchQueue(label: "sideBar.ingestion.uploads")
    private let workQueue = DispatchQueue(label: "sideBar.ingestion.uploads.work", qos: .utility)
    private let workQueueKey = DispatchSpecificKey<Void>()
    private var contexts: [Int: UploadContext] = [:]
    private var taskIdsByUploadId: [String: Int] = [:]
    private var startingUploadIds: Set<String> = []
    private var pendingCanceledUploadIds: Set<String> = []

    public init(config: APIClientConfig, session: URLSession? = nil) {
        self.config = config
        self.providedSession = session
        let pinnedCertificates = PinnedCertificates.loadFromMainBundle()
        if !pinnedCertificates.isEmpty, !EnvironmentConfig.isRunningTestsOrPreviews() {
            self.certificatePinningDelegate = CertificatePinningDelegate(pinnedCertificates: pinnedCertificates)
        } else {
            self.certificatePinningDelegate = nil
        }
        super.init()
        workQueue.setSpecific(key: workQueueKey, value: ())
        // Initialize the lazy session on a single thread to avoid first-access races
        // when start/cancel are called concurrently.
        _ = self.session
    }

    deinit {
        if DispatchQueue.getSpecific(key: workQueueKey) == nil {
            workQueue.sync {}
        }
        session.invalidateAndCancel()
    }

    public func startUpload(
        request: UploadRequest,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) {
        let intent = RequestIntent(
            operation: "files.backgroundUpload",
            path: "files",
            method: .post,
            requestKind: .backgroundUpload,
            authRequirement: .required,
            replaySafety: .notReplaySafe,
            timeoutClass: .long
        )
        let session = self.session
        let logger = self.logger
        let lifecycleClient = APIClient(config: self.config, session: session)

        markUploadStartRequested(uploadId: request.uploadId)
        Task { [weak self] in
            guard let self else { return }
            let urlRequest: URLRequest
            do {
                urlRequest = try await lifecycleClient.buildPreparedRequest(
                    intent.path,
                    method: intent.method,
                    headers: ["Content-Type": "multipart/form-data; boundary=__pending__"],
                    intent: intent
                )
            } catch {
                self.markUploadStartFinished(uploadId: request.uploadId)
                self.dispatchCompletion(onCompletion, result: .failure(error))
                return
            }
            self.enqueuePreparedUploadStart(
                request: request,
                urlRequest: urlRequest,
                session: session,
                logger: logger,
                onProgress: onProgress,
                onCompletion: onCompletion
            )
        }
    }

    private func enqueuePreparedUploadStart(
        request: UploadRequest,
        urlRequest preparedRequest: URLRequest,
        session: URLSession,
        logger: Logger,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) {
        workQueue.async {
            guard self.canProceedWithStart(uploadId: request.uploadId) else {
                self.dispatchCompletion(onCompletion, result: .failure(URLError(.cancelled)))
                return
            }
            let boundary = "Boundary-\(UUID().uuidString)"
            var urlRequest = preparedRequest
            urlRequest.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )

            let bodyURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString)")
            do {
                try IngestionUploadHelpers.writeMultipartBody(
                    to: bodyURL,
                    boundary: boundary,
                    payload: UploadPayload(
                        fileURL: request.fileURL,
                        filename: request.filename,
                        mimeType: request.mimeType,
                        folder: request.folder
                    ),
                    logger: logger
                )
            } catch {
                self.markUploadStartFinished(uploadId: request.uploadId)
                DispatchQueue.main.async { onCompletion(.failure(error)) }
                return
            }

            let task = session.uploadTask(with: urlRequest, fromFile: bodyURL)

            let context = UploadContext(
                uploadId: request.uploadId,
                bodyFileURL: bodyURL,
                onProgress: onProgress,
                onCompletion: onCompletion
            )
            guard self.setContext(context, forTaskId: task.taskIdentifier, uploadId: request.uploadId) else {
                self.dispatchCompletion(onCompletion, result: .failure(URLError(.cancelled)))
                do {
                    try FileManager.default.removeItem(at: bodyURL)
                } catch {
                    logger.error("Failed to remove canceled upload body file: \(error.localizedDescription, privacy: .public)")
                }
                return
            }
            task.resume()
        }
    }

    public func cancelUpload(uploadId: String) {
        let (context, taskId) = takeContext(forUploadId: uploadId)
        if let context {
            dispatchCompletion(context.onCompletion, result: .failure(URLError(.cancelled)))
            do {
                try FileManager.default.removeItem(at: context.bodyFileURL)
            } catch {
                logger.error("Failed to remove canceled upload body file: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard let taskId else { return }
        session.getAllTasks { tasks in
            guard let task = tasks.first(where: { $0.taskIdentifier == taskId }) else {
                return
            }
            task.cancel()
        }
    }

    private func handleCompletion(for task: URLSessionTask, error: Error?) {
        handleCompletion(
            forTaskId: task.taskIdentifier,
            responseData: context(forTaskId: task.taskIdentifier)?.responseData ?? Data(),
            response: task.response,
            error: error,
            intent: RequestIntent(
                operation: "files.backgroundUpload",
                path: "files",
                method: .post,
                requestKind: .backgroundUpload,
                authRequirement: .required,
                replaySafety: .notReplaySafe,
                timeoutClass: .long
            )
        )
    }

    private func handleCompletion(
        forTaskId taskId: Int,
        responseData: Data,
        response: URLResponse?,
        error: Error?,
        intent: RequestIntent
    ) {
        let context = takeContext(forTaskId: taskId)
        guard let context else { return }
        let onCompletion = context.onCompletion
        defer {
            do {
                try FileManager.default.removeItem(at: context.bodyFileURL)
            } catch {
                logger.error("Failed to remove upload body file: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let error {
            if !isCancellationError(error) {
                lifecycleClient.postFailureNotification(intent: intent, transportError: error)
            }
            dispatchCompletion(onCompletion, result: .failure(error))
            return
        }
        guard let response else {
            lifecycleClient.postFailureNotification(intent: intent)
            dispatchCompletion(onCompletion, result: .failure(APIClientError.unknown))
            return
        }
        guard let http = response as? HTTPURLResponse else {
            lifecycleClient.postFailureNotification(intent: intent)
            dispatchCompletion(onCompletion, result: .failure(APIClientError.unknown))
            return
        }
        guard (200...299).contains(http.statusCode) else {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let message = APIClient.decodeErrorMessage(data: responseData, decoder: decoder)
            let appError = AppError.classify(
                operation: intent.operation,
                requestKind: intent.requestKind,
                responseStatus: http.statusCode,
                backendMessage: message,
                transportError: nil
            )
            lifecycleClient.postFailureNotification(intent: intent, appError: appError)
            dispatchCompletion(onCompletion, result: .failure(APIClientError.appError(appError)))
            return
        }
        do {
            let fileId = try IngestionUploadHelpers.parseUploadResponse(data: responseData)
            lifecycleClient.postSuccessNotification(intent: intent, statusCode: http.statusCode)
            dispatchCompletion(onCompletion, result: .success(fileId))
        } catch {
            let appError = AppError.classify(
                error: APIClientError.decodingFailed,
                operation: intent.operation,
                requestKind: intent.requestKind
            )
            lifecycleClient.postFailureNotification(intent: intent, appError: appError)
            dispatchCompletion(onCompletion, result: .failure(error))
        }
    }

    private func dispatchCompletion(
        _ onCompletion: @escaping (Result<String, Error>) -> Void,
        result: Result<String, Error>
    ) {
        DispatchQueue.main.async {
            onCompletion(result)
        }
    }

    private var lifecycleClient: APIClient {
        APIClient(config: config, session: session)
    }

    private func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func setContext(_ context: UploadContext, forTaskId taskId: Int, uploadId: String) -> Bool {
        queue.sync {
            defer { startingUploadIds.remove(uploadId) }
            guard pendingCanceledUploadIds.remove(uploadId) == nil else {
                return false
            }
            contexts[taskId] = context
            taskIdsByUploadId[uploadId] = taskId
            return true
        }
    }

    private func taskId(forUploadId uploadId: String) -> Int? {
        queue.sync {
            taskIdsByUploadId[uploadId]
        }
    }

    private func context(forTaskId taskId: Int) -> UploadContext? {
        queue.sync {
            contexts[taskId]
        }
    }

    private func appendResponseData(_ data: Data, forTaskId taskId: Int) {
        queue.sync {
            contexts[taskId]?.responseData.append(data)
        }
    }

    private func takeContext(forTaskId taskId: Int) -> UploadContext? {
        queue.sync {
            guard let context = contexts.removeValue(forKey: taskId) else {
                return nil
            }
            taskIdsByUploadId.removeValue(forKey: context.uploadId)
            return context
        }
    }

    private func takeContext(forUploadId uploadId: String) -> (UploadContext?, Int?) {
        queue.sync {
            guard let taskId = taskIdsByUploadId.removeValue(forKey: uploadId) else {
                pendingCanceledUploadIds.insert(uploadId)
                expirePendingCancellation(uploadId: uploadId)
                return (nil, nil)
            }
            let context = contexts.removeValue(forKey: taskId)
            return (context, taskId)
        }
    }

    private func markUploadStartRequested(uploadId: String) {
        _ = queue.sync {
            startingUploadIds.insert(uploadId)
        }
    }

    private func canProceedWithStart(uploadId: String) -> Bool {
        queue.sync {
            guard pendingCanceledUploadIds.remove(uploadId) == nil else {
                startingUploadIds.remove(uploadId)
                return false
            }
            return true
        }
    }

    private func markUploadStartFinished(uploadId: String) {
        _ = queue.sync {
            startingUploadIds.remove(uploadId)
        }
    }

    private func expirePendingCancellation(uploadId: String) {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.pendingCanceledUploadIds.remove(uploadId)
        }
    }

}

extension IngestionUploadManager: URLSessionTaskDelegate, URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let certificatePinningDelegate else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        certificatePinningDelegate.urlSession(
            session,
            didReceive: challenge,
            completionHandler: completionHandler
        )
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        guard let onProgress = context(forTaskId: task.taskIdentifier)?.onProgress else { return }
        DispatchQueue.main.async { onProgress(progress) }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        appendResponseData(data, forTaskId: dataTask.taskIdentifier)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        handleCompletion(for: task, error: error)
    }
}

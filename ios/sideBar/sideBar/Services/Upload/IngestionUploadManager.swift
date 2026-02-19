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

struct UploadPayload {
    let fileURL: URL
    let filename: String
    let mimeType: String
    let folder: String
}

private struct UploadResponse: Decodable {
    let fileId: String?
    let data: UploadResponseData?
}

private struct UploadResponseData: Decodable {
    let fileId: String?
}

/// Handles background uploads for ingestion.
public final class IngestionUploadManager: NSObject, IngestionUploadManaging {
    private let config: APIClientConfig
    private let logger = Logger(subsystem: "sideBar", category: "Upload")
    private let providedSession: URLSession?
    private let certificatePinningDelegate: CertificatePinningDelegate?
    private lazy var session: URLSession = {
        if let providedSession {
            return providedSession
        }
        #if os(iOS)
        let configuration: URLSessionConfiguration
        if EnvironmentConfig.isRunningTestsOrPreviews() {
            configuration = URLSessionConfiguration.default
        } else {
            configuration = URLSessionConfiguration.background(withIdentifier: "sideBar.ingestion.uploads")
            configuration.sessionSendsLaunchEvents = true
            configuration.isDiscretionary = false
        }
        #else
        let configuration = URLSessionConfiguration.default
        #endif
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
        if providedSession == nil {
            session.invalidateAndCancel()
        }
    }

    public func startUpload(
        request: UploadRequest,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) {
        let baseUrl = config.baseUrl
        let accessTokenProvider = config.accessTokenProvider
        let session = self.session
        let logger = self.logger

        markUploadStartRequested(uploadId: request.uploadId)
        workQueue.async {
            guard self.canProceedWithStart(uploadId: request.uploadId) else {
                self.dispatchCompletion(onCompletion, result: .failure(URLError(.cancelled)))
                return
            }
            let boundary = "Boundary-\(UUID().uuidString)"
            var urlRequest = URLRequest(url: baseUrl.appendingPathComponent("files"))
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = accessTokenProvider() {
                urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

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
        let context = takeContext(forTaskId: task.taskIdentifier)
        guard let context else { return }
        let onCompletion = context.onCompletion
        let responseData = context.responseData
        defer {
            do {
                try FileManager.default.removeItem(at: context.bodyFileURL)
            } catch {
                logger.error("Failed to remove upload body file: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let error {
            dispatchCompletion(onCompletion, result: .failure(error))
            return
        }
        guard let response = task.response as? HTTPURLResponse else {
            dispatchCompletion(onCompletion, result: .failure(APIClientError.unknown))
            return
        }
        guard (200...299).contains(response.statusCode) else {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let message = APIClient.decodeErrorMessage(data: responseData, decoder: decoder) {
                dispatchCompletion(onCompletion, result: .failure(APIClientError.apiError(message)))
                return
            }
            dispatchCompletion(onCompletion, result: .failure(APIClientError.requestFailed(response.statusCode)))
            return
        }
        do {
            let fileId = try IngestionUploadHelpers.parseUploadResponse(data: responseData)
            dispatchCompletion(onCompletion, result: .success(fileId))
        } catch {
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
        queue.sync {
            _ = startingUploadIds.insert(uploadId)
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
        queue.sync {
            _ = startingUploadIds.remove(uploadId)
        }
    }

    private func expirePendingCancellation(uploadId: String) {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.pendingCanceledUploadIds.remove(uploadId)
        }
    }

}

enum IngestionUploadHelpers {
    static func writeMultipartBody(
        to url: URL,
        boundary: String,
        payload: UploadPayload,
        logger: Logger
    ) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer {
            do {
                try handle.close()
            } catch {
                logger.error("Upload body file close failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"folder\"\r\n\r\n".utf8))
        try handle.write(contentsOf: Data("\(payload.folder)\r\n".utf8))
        try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(payload.filename)\"\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Type: \(payload.mimeType)\r\n\r\n".utf8))

        let input = try FileHandle(forReadingFrom: payload.fileURL)
        defer {
            do {
                try input.close()
            } catch {
                logger.error("Upload source file close failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        var writeError: Error?
        while autoreleasepool(invoking: {
            let chunk = input.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty {
                return false
            }
            do {
                try handle.write(contentsOf: chunk)
            } catch {
                writeError = error
                return false
            }
            return true
        }) { }
        if let writeError {
            throw writeError
        }

        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }

    static func parseUploadResponse(data: Data) throws -> String {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(UploadResponse.self, from: data)
        if let fileId = payload.fileId {
            return fileId
        }
        if let fileId = payload.data?.fileId {
            return fileId
        }
        throw APIClientError.decodingFailed
    }
}

private final class UploadContext {
    let uploadId: String
    let bodyFileURL: URL
    let onProgress: (Double) -> Void
    let onCompletion: (Result<String, Error>) -> Void
    var responseData = Data()

    init(
        uploadId: String,
        bodyFileURL: URL,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) {
        self.uploadId = uploadId
        self.bodyFileURL = bodyFileURL
        self.onProgress = onProgress
        self.onCompletion = onCompletion
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

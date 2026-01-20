import Foundation
import OSLog

// MARK: - IngestionUploadManager

public protocol IngestionUploadManaging: AnyObject {
    func startUpload(
        uploadId: String,
        fileURL: URL,
        filename: String,
        mimeType: String,
        folder: String,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    )
    func cancelUpload(uploadId: String)
}

/// Handles background uploads for ingestion.
public final class IngestionUploadManager: NSObject, IngestionUploadManaging {
    private let config: APIClientConfig
    private let logger = Logger(subsystem: "sideBar", category: "Upload")
    private lazy var session: URLSession = {
        #if os(iOS)
        let configuration = URLSessionConfiguration.background(withIdentifier: "sideBar.ingestion.uploads")
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        #else
        let configuration = URLSessionConfiguration.default
        #endif
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private let queue = DispatchQueue(label: "sideBar.ingestion.uploads")
    private var contexts: [Int: UploadContext] = [:]
    private var taskIdsByUploadId: [String: Int] = [:]

    public init(config: APIClientConfig) {
        self.config = config
        super.init()
    }

    public func startUpload(
        uploadId: String,
        fileURL: URL,
        filename: String,
        mimeType: String,
        folder: String,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: self.config.baseUrl.appendingPathComponent("files"))
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = self.config.accessTokenProvider() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let bodyURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString)")
            do {
                try IngestionUploadHelpers.writeMultipartBody(
                    to: bodyURL,
                    boundary: boundary,
                    fileURL: fileURL,
                    filename: filename,
                    mimeType: mimeType,
                    folder: folder,
                    logger: self.logger
                )
            } catch {
                DispatchQueue.main.async { onCompletion(.failure(error)) }
                return
            }

            let task = self.session.uploadTask(with: request, fromFile: bodyURL)
            let context = UploadContext(
                uploadId: uploadId,
                bodyFileURL: bodyURL,
                onProgress: onProgress,
                onCompletion: onCompletion
            )
            self.queue.async {
                self.contexts[task.taskIdentifier] = context
                self.taskIdsByUploadId[uploadId] = task.taskIdentifier
            }
            task.resume()
        }
    }

    public func cancelUpload(uploadId: String) {
        queue.async {
            guard let taskId = self.taskIdsByUploadId[uploadId],
                  let task = self.session.getAllTasksSync().first(where: { $0.taskIdentifier == taskId }) else {
                return
            }
            task.cancel()
        }
    }

    private func handleCompletion(for task: URLSessionTask, error: Error?) {
        let context = queue.sync { contexts[task.taskIdentifier] }
        guard let context else { return }
        queue.async {
            self.contexts.removeValue(forKey: task.taskIdentifier)
            self.taskIdsByUploadId.removeValue(forKey: context.uploadId)
        }
        defer {
            do {
                try FileManager.default.removeItem(at: context.bodyFileURL)
            } catch {
                logger.error("Failed to remove upload body file: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let error {
            DispatchQueue.main.async { context.onCompletion(.failure(error)) }
            return
        }
        guard let response = task.response as? HTTPURLResponse else {
            DispatchQueue.main.async { context.onCompletion(.failure(APIClientError.unknown)) }
            return
        }
        guard (200...299).contains(response.statusCode) else {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let message = APIClient.decodeErrorMessage(data: context.responseData, decoder: decoder) {
                DispatchQueue.main.async { context.onCompletion(.failure(APIClientError.apiError(message))) }
                return
            }
            DispatchQueue.main.async { context.onCompletion(.failure(APIClientError.requestFailed(response.statusCode))) }
            return
        }
        do {
            let fileId = try IngestionUploadHelpers.parseUploadResponse(data: context.responseData)
            DispatchQueue.main.async { context.onCompletion(.success(fileId)) }
        } catch {
            DispatchQueue.main.async { context.onCompletion(.failure(error)) }
        }
    }

}

enum IngestionUploadHelpers {
    static func writeMultipartBody(
        to url: URL,
        boundary: String,
        fileURL: URL,
        filename: String,
        mimeType: String,
        folder: String,
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
        try handle.write(contentsOf: Data("\(folder)\r\n".utf8))
        try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

        let input = try FileHandle(forReadingFrom: fileURL)
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
        struct UploadResponse: Decodable {
            let fileId: String?
            let data: Inner?

            struct Inner: Decodable {
                let fileId: String?
            }
        }

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

private extension URLSession {
    func getAllTasksSync() -> [URLSessionTask] {
        let semaphore = DispatchSemaphore(value: 0)
        var tasks: [URLSessionTask] = []
        getAllTasks { fetched in
            tasks = fetched
            semaphore.signal()
        }
        semaphore.wait()
        return tasks
    }
}

extension IngestionUploadManager: URLSessionTaskDelegate, URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        guard let context = queue.sync(execute: { contexts[task.taskIdentifier] }) else { return }
        DispatchQueue.main.async { context.onProgress(progress) }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.sync {
            contexts[dataTask.taskIdentifier]?.responseData.append(data)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        handleCompletion(for: task, error: error)
    }
}

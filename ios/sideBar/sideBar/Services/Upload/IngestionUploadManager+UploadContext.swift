import Foundation

final class UploadContext {
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

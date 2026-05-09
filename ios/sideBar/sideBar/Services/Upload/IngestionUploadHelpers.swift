import Foundation
import OSLog
import sideBarShared

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

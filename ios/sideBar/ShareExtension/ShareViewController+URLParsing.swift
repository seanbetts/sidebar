import Foundation

struct ShareItemProviderLoadResult<Value> {
    let value: Value?
    let error: Error?
}

extension ShareViewController {
    // MARK: - URL Parsing Helpers

    func loadURL(from itemProvider: NSItemProvider, typeIdentifier: String) async throws -> URL? {
        let itemResult = await loadItemResult(from: itemProvider, typeIdentifier: typeIdentifier)
        if let item = itemResult.value,
           let url = urlFromTextPayload(item) {
            return url
        }
        let dataResult = await loadDataResult(from: itemProvider, typeIdentifier: typeIdentifier)
        if let data = dataResult.value,
           let url = urlFromTextPayload(data) {
            return url
        }
        if let error = itemResult.error ?? dataResult.error {
            throw error
        }
        return nil
    }

    func urlFromTextPayload(_ item: Any?) -> URL? {
        if let url = item as? URL {
            if url.isFileURL, let fileURL = extractURLFromFile(url) {
                return fileURL
            }
            return url
        }
        if let attributed = item as? NSAttributedString {
            if let url = extractFirstLink(from: attributed) {
                return url
            }
            return extractFirstURL(from: attributed.string)
        }
        if let string = item as? String {
            return extractFirstURL(from: string)
        }
        if let string = item as? NSString {
            return extractFirstURL(from: string as String)
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return extractFirstURL(from: string)
        }
        return nil
    }

    func extractFirstLink(from attributed: NSAttributedString) -> URL? {
        var found: URL?
        let range = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.link, in: range, options: []) { value, _, stop in
            if let url = value as? URL {
                found = url
                stop.pointee = true
            } else if let string = value as? String, let url = URL(string: string) {
                found = url
                stop.pointee = true
            }
        }
        return found
    }

    func extractFirstURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              let url = match.url else {
            return nil
        }
        return url
    }

    func extractURLFromFile(_ url: URL) -> URL? {
        guard let string = readTextFile(url) else { return nil }
        return extractFirstURL(from: string)
    }

    func readTextFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let maxBytes = 64 * 1024
        let limitedData = data.count > maxBytes ? data.prefix(maxBytes) : data
        return String(data: limitedData, encoding: .utf8)
    }

    // MARK: - Item Loading Helpers

    func loadItemResult(from itemProvider: NSItemProvider, typeIdentifier: String) async -> ShareItemProviderLoadResult<Any> {
        await withCheckedContinuation { continuation in
            itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                continuation.resume(
                    returning: ShareItemProviderLoadResult(
                        value: item,
                        error: error
                    )
                )
            }
        }
    }

    func loadDataResult(from itemProvider: NSItemProvider, typeIdentifier: String) async -> ShareItemProviderLoadResult<Data> {
        await withCheckedContinuation { continuation in
            itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                continuation.resume(
                    returning: ShareItemProviderLoadResult(
                        value: data,
                        error: error
                    )
                )
            }
        }
    }

    // MARK: - MIME Type Helper

    func mimeTypeForFilename(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        let mappings: [String: String] = [
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "gif": "image/gif",
            "heic": "image/heic",
            "heif": "image/heic",
            "htm": "text/html",
            "html": "text/html",
            "jpeg": "image/jpeg",
            "jpg": "image/jpeg",
            "json": "application/json",
            "mov": "video/quicktime",
            "mp3": "audio/mpeg",
            "mp4": "video/mp4",
            "pdf": "application/pdf",
            "png": "image/png",
            "ppt": "application/vnd.ms-powerpoint",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "txt": "text/plain",
            "webp": "image/webp",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "xml": "application/xml",
            "zip": "application/zip"
        ]
        return mappings[ext] ?? "application/octet-stream"
    }
}

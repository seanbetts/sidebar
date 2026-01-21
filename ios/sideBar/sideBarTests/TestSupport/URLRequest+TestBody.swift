import Foundation

extension URLRequest {
    func httpBodyData() -> Data? {
        if let body = httpBody {
            return body
        }
        guard let stream = httpBodyStream else {
            return nil
        }
        return stream.readAllData()
    }
}

private extension InputStream {
    func readAllData() -> Data? {
        open()
        defer { close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while hasBytesAvailable {
            let readCount = read(&buffer, maxLength: buffer.count)
            if readCount < 0 {
                return nil
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }
        return data
    }
}

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct MarkdownFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sideBarMarkdown] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let content = String(data: data, encoding: .utf8) {
            text = content
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static var sideBarMarkdown: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }
}

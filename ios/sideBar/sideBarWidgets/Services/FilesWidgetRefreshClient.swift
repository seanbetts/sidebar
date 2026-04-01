import Foundation
import sideBarShared

struct FilesWidgetRefreshClient {
    private let apiClient: APIClient

    init(environment: WidgetAPIEnvironment) {
        self.apiClient = environment.apiClient
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func refreshPinnedFiles(now: Date = Date()) async throws -> WidgetFileData {
        let response: FilesWidgetListResponse = try await apiClient.request("files")
        let pinnedFiles = response.items
            .filter { $0.file.pinned == true && $0.file.deletedAt == nil }
            .sorted { ($0.file.pinnedOrder ?? Int.max) < ($1.file.pinnedOrder ?? Int.max) }
            .map { WidgetFile(from: $0) }

        return WidgetFileData(
            files: Array(pinnedFiles.prefix(10)),
            totalCount: pinnedFiles.count,
            lastUpdated: now
        )
    }
}

private struct FilesWidgetListResponse: Decodable {
    let items: [FilesWidgetListItem]
}

private struct FilesWidgetListItem: Decodable {
    let file: FilesWidgetFilePayload
    let recommendedViewer: String?
}

private struct FilesWidgetFilePayload: Decodable {
    let id: String
    let filenameOriginal: String
    let path: String?
    let mimeOriginal: String
    let sizeBytes: Int
    let pinned: Bool?
    let pinnedOrder: Int?
    let category: String?
    let deletedAt: String?
}

private extension WidgetFile {
    init(from item: FilesWidgetListItem) {
        self.init(
            id: item.file.id,
            filename: item.file.filenameOriginal,
            path: item.file.path,
            sizeBytes: item.file.sizeBytes,
            pinned: item.file.pinned ?? false,
            category: item.file.category,
            mimeType: item.file.mimeOriginal,
            recommendedViewer: item.recommendedViewer
        )
    }
}

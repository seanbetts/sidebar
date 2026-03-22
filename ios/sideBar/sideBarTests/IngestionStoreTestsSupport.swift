import Foundation
import sideBarShared
@testable import sideBar

enum IngestionStoreTestsSupport {
    enum MockError: Error {
        case forced
    }

    struct MockIngestionAPI: IngestionProviding {
        let listResponse: IngestionListResponse?

        init(listResponse: IngestionListResponse? = nil) {
            self.listResponse = listResponse
        }

        func list() async throws -> IngestionListResponse {
            if let listResponse {
                return listResponse
            }
            throw MockError.forced
        }

        func getMeta(fileId: String) async throws -> IngestionMetaResponse {
            _ = fileId
            throw MockError.forced
        }

        func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
            _ = fileId
            _ = kind
            _ = range
            throw MockError.forced
        }

        func cancel(fileId: String) async throws {
            _ = fileId
            throw MockError.forced
        }

        func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
            _ = fileId
            _ = pinned
            _ = clientUpdatedAt
            throw MockError.forced
        }

        func updatePinnedOrder(ids: [String]) async throws {
            _ = ids
            throw MockError.forced
        }

        func delete(fileId: String, clientUpdatedAt: String?) async throws {
            _ = fileId
            _ = clientUpdatedAt
            throw MockError.forced
        }

        func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
            _ = fileId
            _ = filename
            _ = clientUpdatedAt
            throw MockError.forced
        }

        func ingestYouTube(url: String) async throws -> String {
            _ = url
            throw MockError.forced
        }

        func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
            _ = payload
            throw MockError.forced
        }
    }

    static func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "IngestionStoreTests") ?? .standard
        defaults.removePersistentDomain(forName: "IngestionStoreTests")
        return defaults
    }

    static func makeItem(
        id: String,
        filename: String = "doc.txt",
        path: String = "/doc.txt",
        mimeOriginal: String = "text/plain",
        sourceMetadata: [String: AnyCodable]? = nil,
        sourceUrl: String? = nil,
        pinned: Bool? = nil,
        pinnedOrder: Int? = nil,
        status: String = "processing",
        stage: String = "extracting",
        recommendedViewer: String? = nil,
        deletedAt: String? = nil
    ) -> IngestionListItem {
        IngestionListItem(
            file: IngestedFileMeta(
                id: id,
                filenameOriginal: filename,
                path: path,
                mimeOriginal: mimeOriginal,
                sizeBytes: 12,
                sha256: nil,
                pinned: pinned,
                pinnedOrder: pinnedOrder,
                category: nil,
                sourceUrl: sourceUrl,
                sourceMetadata: sourceMetadata,
                createdAt: "2024-01-01T12:00:00Z",
                updatedAt: "2024-01-01T12:00:00Z",
                deletedAt: deletedAt
            ),
            job: IngestionJob(
                status: status,
                stage: stage,
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 0,
                updatedAt: "2024-01-01T12:00:00Z"
            ),
            recommendedViewer: recommendedViewer
        )
    }

    static func makeMeta(
        fileID: String,
        status: String,
        stage: String,
        updatedAt: String,
        recommendedViewer: String?
    ) -> IngestionMetaResponse {
        IngestionMetaResponse(
            file: IngestedFileMeta(
                id: fileID,
                filenameOriginal: "\(fileID).txt",
                path: "/\(fileID).txt",
                mimeOriginal: "text/plain",
                sizeBytes: 12,
                sha256: nil,
                pinned: false,
                pinnedOrder: nil,
                category: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-01-10T00:00:00Z",
                updatedAt: updatedAt,
                deletedAt: nil
            ),
            job: IngestionJob(
                status: status,
                stage: stage,
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 0,
                updatedAt: updatedAt
            ),
            derivatives: [
                IngestionDerivative(
                    id: "\(fileID)-d1",
                    kind: "text_original",
                    storageKey: "derivatives/\(fileID)/text_original",
                    mime: "text/plain",
                    sizeBytes: 12
                )
            ],
            recommendedViewer: recommendedViewer
        )
    }
}

import XCTest
@testable import sideBar

@MainActor
final class IngestionViewModelPollingStressTests: XCTestCase {
    func testRepeatedStartAndCancelPollingDoesNotLeakTasksOrTokens() async {
        let viewModel = makePollingViewModel(fileId: "file-1", jobStatus: "processing")

        for cycle in 0..<40 {
            viewModel.startJobPollingIfNeeded(fileId: "file-1")
            if cycle.isMultiple(of: 3) {
                viewModel.startJobPollingIfNeeded(fileId: "file-1")
            }
            if cycle.isMultiple(of: 2) {
                viewModel.cancelJobPolling(fileId: "file-1")
            } else {
                viewModel.cancelJobPolling()
            }

            XCTAssertTrue(viewModel.jobPollingTasks.isEmpty, "Cycle \(cycle) leaked polling tasks")
            XCTAssertTrue(viewModel.jobPollingTaskTokens.isEmpty, "Cycle \(cycle) leaked polling tokens")
        }
    }

    private func makePollingViewModel(fileId: String, jobStatus: String) -> IngestionViewModel {
        let meta = IngestionMetaResponse(
            file: makeFile(id: fileId),
            job: makeJob(status: jobStatus),
            derivatives: [],
            recommendedViewer: nil
        )
        let api = PollingStressIngestionAPI(meta: meta)
        let store = IngestionStore(
            api: api,
            cache: TestCacheClient(),
            userDefaults: makeDefaults()
        )
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: NoopIngestionUploadManager(),
            toastCenter: ToastCenter()
        )
        viewModel.selectedFileId = fileId
        viewModel.activeMeta = meta
        return viewModel
    }

    private func makeFile(id: String) -> IngestedFileMeta {
        IngestedFileMeta(
            id: id,
            filenameOriginal: "file.txt",
            path: nil,
            mimeOriginal: "text/plain",
            sizeBytes: 10,
            sha256: nil,
            pinned: false,
            pinnedOrder: nil,
            category: nil,
            sourceUrl: nil,
            sourceMetadata: nil,
            createdAt: "2026-01-10T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
    }

    private func makeJob(status: String, stage: String = "processing") -> IngestionJob {
        IngestionJob(
            status: status,
            stage: stage,
            errorCode: nil,
            errorMessage: nil,
            userMessage: nil,
            progress: nil,
            attempts: 1,
            updatedAt: nil
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "IngestionViewModelPollingStressTests"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private enum PollingStressError: Error {
    case forced
}

private struct PollingStressIngestionAPI: IngestionProviding {
    let meta: IngestionMetaResponse

    func list() async throws -> IngestionListResponse {
        IngestionListResponse(items: [])
    }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        _ = fileId
        return meta
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = fileId
        _ = kind
        _ = range
        throw PollingStressError.forced
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
    }

    func delete(fileId: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = clientUpdatedAt
        throw PollingStressError.forced
    }

    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = filename
        _ = clientUpdatedAt
        throw PollingStressError.forced
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        throw PollingStressError.forced
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        return IngestionSyncResponse(applied: [], files: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
    }
}

private final class NoopIngestionUploadManager: IngestionUploadManaging {
    func startUpload(
        request: UploadRequest,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) {
        _ = request
        _ = onProgress
        _ = onCompletion
    }

    func cancelUpload(uploadId: String) {
        _ = uploadId
    }
}

import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class IngestionHeaderStatusTests: XCTestCase {
    func testIngestionHeaderSnapshotExposesOnlyCancelForActiveRows() async {
        let viewModel = makeViewModel(items: [makeItem(id: "local-1", status: "uploading", stage: "uploading")])

        let snapshot = viewModel.headerStatusSnapshot

        guard case let .active(rows)? = snapshot else {
            return XCTFail("Expected active ingestion snapshot")
        }
        XCTAssertEqual(rows.first?.actions.map(\.title), ["Cancel"])
    }

    func testIngestionHeaderSnapshotPrefersActiveRowsOverReadyEvent() async {
        let viewModel = makeViewModel(items: [makeItem(id: "local-1", status: "uploading", stage: "uploading")])

        viewModel.registerHeaderReadyEvent(.init(fileId: "file-1", filename: "Quarterly report"))

        guard case .active? = viewModel.headerStatusSnapshot else {
            return XCTFail("Expected active ingestion snapshot to win over terminal event")
        }
    }

    func testIngestionHeaderSnapshotUsesReadyEventForInformationalState() async {
        let viewModel = makeViewModel(items: [])

        viewModel.registerHeaderReadyEvent(.init(fileId: "file-1", filename: "Quarterly report"))

        guard case let .success(messageID, title, _)? = viewModel.headerStatusSnapshot else {
            return XCTFail("Expected ready informational snapshot")
        }
        XCTAssertEqual(messageID, "file-1")
        XCTAssertEqual(title, "Ready")
    }

    func testIngestionHeaderSnapshotUsesFailureWithoutActionForTerminalError() async {
        let viewModel = makeViewModel(items: [makeItem(id: "failed-file-1", status: "failed", stage: "failed")])

        guard case let .failureWithoutAction(messageID, title, _)? = viewModel.headerStatusSnapshot else {
            return XCTFail("Expected terminal failure informational snapshot")
        }
        XCTAssertEqual(messageID, "failed-file-1")
        XCTAssertEqual(title, "Upload failed")
    }

    func testIngestionHeaderReadyRegistrationSourceDoesNotSleep() throws {
        let normalized = try ingestionHeaderSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("Task.sleep"))
    }

    private func makeViewModel(items: [IngestionListItem]) -> IngestionViewModel {
        let api = MockIngestionAPI()
        let store = IngestionStore(
            api: api,
            cache: TestCacheClient(),
            userDefaults: makeIngestionHeaderDefaults()
        )
        items.forEach { store.addLocalUpload($0) }

        return IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockIngestionUploadManager(),
            toastCenter: ToastCenter()
        )
    }

    private func makeItem(id: String, status: String, stage: String) -> IngestionListItem {
        IngestionListItem(
            file: IngestedFileMeta(
                id: id,
                filenameOriginal: "Quarterly report.pdf",
                path: nil,
                mimeOriginal: "application/pdf",
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
            ),
            job: IngestionJob(
                status: status,
                stage: stage,
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 1,
                updatedAt: nil
            ),
            recommendedViewer: "viewer_pdf"
        )
    }
}

private func ingestionHeaderSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("ViewModels")
        .appendingPathComponent("IngestionViewModel+HeaderStatus.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read IngestionViewModel+HeaderStatus.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func makeIngestionHeaderDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "IngestionHeaderStatusTests") ?? .standard
    defaults.removePersistentDomain(forName: "IngestionHeaderStatusTests")
    return defaults
}

private struct MockIngestionAPI: IngestionProviding {
    func list() async throws -> IngestionListResponse {
        IngestionListResponse(items: [])
    }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        _ = fileId
        throw MockIngestionError.forced
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = fileId
        _ = kind
        _ = range
        throw MockIngestionError.forced
    }

    func upload(fileURL: URL, filename: String, mimeType: String, folder: String) async throws -> String {
        _ = fileURL
        _ = filename
        _ = mimeType
        _ = folder
        throw MockIngestionError.forced
    }

    func cancel(fileId: String) async throws {
        _ = fileId
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func delete(fileId: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = clientUpdatedAt
        throw MockIngestionError.forced
    }

    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = filename
        _ = clientUpdatedAt
        throw MockIngestionError.forced
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        throw MockIngestionError.forced
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        return IngestionSyncResponse(applied: [], files: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
    }
}

private enum MockIngestionError: Error {
    case forced
}

private final class MockIngestionUploadManager: IngestionUploadManaging {
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

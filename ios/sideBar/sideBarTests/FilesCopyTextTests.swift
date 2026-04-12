import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class FilesCopyTextTests: XCTestCase {
    func testCanCopyTextReturnsTrueForPlainTextItem() {
        let fixture = makeFixture(items: [makeItem(id: "text-file", mimeType: "text/plain", recommendedViewer: "text_original")])
        let item = makeItem(
            id: "text-file",
            mimeType: "text/plain",
            recommendedViewer: "text_original"
        )

        let canCopy = fixture.viewModel.canCopyText(for: item)

        XCTAssertTrue(canCopy)
    }

    func testCanCopyTextReturnsFalseForMediaItems() {
        let fixture = makeFixture(items: [
            makeItem(id: "image-file", mimeType: "image/png", recommendedViewer: "image_original"),
            makeItem(id: "audio-file", mimeType: "audio/mpeg", recommendedViewer: "audio_original"),
            makeItem(id: "video-file", mimeType: "video/mp4", recommendedViewer: "viewer_video")
        ])

        XCTAssertFalse(
            fixture.viewModel.canCopyText(
                for: makeItem(id: "image-file", mimeType: "image/png", recommendedViewer: "image_original")
            )
        )
        XCTAssertFalse(
            fixture.viewModel.canCopyText(
                for: makeItem(id: "audio-file", mimeType: "audio/mpeg", recommendedViewer: "audio_original")
            )
        )
        XCTAssertFalse(
            fixture.viewModel.canCopyText(
                for: makeItem(id: "video-file", mimeType: "video/mp4", recommendedViewer: "viewer_video")
            )
        )
    }

    func testLoadCopyTextContentReturnsViewerTextWithoutRefetching() async {
        let file = makeFile(id: "text-file", mimeType: "text/plain")
        let meta = makeMeta(
            file: file,
            derivatives: [
                makeDerivative(kind: "text_original", mimeType: "text/plain")
            ],
            recommendedViewer: "text_original"
        )
        let recorder = IngestionRequestRecorder()
        let fixture = makeFixture(
            items: [makeItem(id: file.id, mimeType: file.mimeOriginal, recommendedViewer: "text_original")],
            api: FilesCopyTextAPI(
                metaByFileId: [file.id: meta],
                contentByFileIdAndKind: [file.id: ["text_original": Data("Hello".utf8)]],
                recorder: recorder
            )
        )
        fixture.store.activeMeta = meta
        fixture.viewModel.selectedFileId = file.id
        fixture.viewModel.viewerState = FileViewerState(
            title: file.filenameOriginal,
            kind: .text,
            text: "Already loaded",
            fileURL: nil,
            spreadsheet: nil,
            youtubeEmbedURL: nil
        )

        let result = await fixture.viewModel.loadCopyTextContent(fileId: file.id)
        let metaRequests = await recorder.metaRequests()
        let contentRequests = await recorder.contentRequests()

        XCTAssertEqual(result, "Already loaded")
        XCTAssertEqual(metaRequests, [])
        XCTAssertEqual(contentRequests, [])
    }

    func testLoadCopyTextContentFetchesPlainTextWithoutChangingSelectionOrViewerState() async {
        let selectedViewerState = FileViewerState(
            title: "Other.txt",
            kind: .text,
            text: "Keep me",
            fileURL: nil,
            spreadsheet: nil,
            youtubeEmbedURL: nil
        )
        let file = makeFile(id: "text-file", mimeType: "text/plain")
        let meta = makeMeta(
            file: file,
            derivatives: [
                makeDerivative(kind: "text_original", mimeType: "text/plain")
            ],
            recommendedViewer: "text_original"
        )
        let recorder = IngestionRequestRecorder()
        let fixture = makeFixture(
            items: [makeItem(id: file.id, mimeType: file.mimeOriginal, recommendedViewer: "text_original")],
            api: FilesCopyTextAPI(
                metaByFileId: [file.id: meta],
                contentByFileIdAndKind: [file.id: ["text_original": Data("Hello from file".utf8)]],
                recorder: recorder
            )
        )
        fixture.viewModel.selectedFileId = "other-file"
        fixture.viewModel.viewerState = selectedViewerState

        let result = await fixture.viewModel.loadCopyTextContent(fileId: file.id)
        let metaRequests = await recorder.metaRequests()
        let contentRequests = await recorder.contentRequests()

        XCTAssertEqual(result, "Hello from file")
        XCTAssertEqual(fixture.viewModel.selectedFileId, "other-file")
        XCTAssertEqual(fixture.viewModel.viewerState?.title, selectedViewerState.title)
        XCTAssertEqual(fixture.viewModel.viewerState?.text, selectedViewerState.text)
        XCTAssertEqual(metaRequests, [file.id])
        XCTAssertEqual(
            contentRequests,
            [CopyContentRequest(fileId: file.id, kind: "text_original")]
        )
    }

    func testLoadCopyTextContentReturnsNilForVideoFiles() async {
        let file = makeFile(id: "video-file", mimeType: "video/mp4", filename: "clip.mp4")
        let meta = makeMeta(
            file: file,
            derivatives: [
                makeDerivative(kind: "video_original", mimeType: "video/mp4"),
                makeDerivative(kind: "ai_md", mimeType: "text/markdown")
            ],
            recommendedViewer: "viewer_video"
        )
        let recorder = IngestionRequestRecorder()
        let fixture = makeFixture(
            items: [makeItem(id: file.id, mimeType: file.mimeOriginal, recommendedViewer: "viewer_video")],
            api: FilesCopyTextAPI(
                metaByFileId: [file.id: meta],
                contentByFileIdAndKind: [file.id: ["ai_md": Data("Transcript".utf8)]],
                recorder: recorder
            )
        )

        let result = await fixture.viewModel.loadCopyTextContent(fileId: file.id)
        let metaRequests = await recorder.metaRequests()
        let contentRequests = await recorder.contentRequests()

        XCTAssertNil(result)
        XCTAssertEqual(metaRequests, [file.id])
        XCTAssertEqual(contentRequests, [])
    }

    func testFilesPanelContextMenuOmitsCopyTextForMediaItems() {
        let imageItem = makeItem(id: "image-file", mimeType: "image/png", recommendedViewer: "image_original")
        let textItem = makeItem(id: "text-file", mimeType: "text/plain", recommendedViewer: "text_original")
        let fixture = makeFixture(items: [textItem, imageItem])
        let view = FilesPanelView(viewModel: fixture.viewModel, showsHeader: false)

        let textTitles = view.fileContextMenuItemsList(for: textItem).map(\.title)
        let imageTitles = view.fileContextMenuItemsList(for: imageItem).map(\.title)

        XCTAssertTrue(textTitles.contains("Copy Text"))
        XCTAssertFalse(imageTitles.contains("Copy Text"))
    }

    func testFilesPanelCopyTextActionDoesNotSelectFileBeforeCopying() throws {
        let normalized = try filesSource(named: "FilesPanel+ContextMenu.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".copyText{Task{awaitcopyTextContent(for:item)}}"))
        XCTAssertFalse(normalized.contains(".copyText{Task{awaitselectFileForAction(item)"))
    }

    func testFilesHeaderShowsCopyTextOnlyWhenSelectedFileSupportsIt() throws {
        let normalized = try filesSource(named: "FilesHeaderActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("ifviewModel.canCopyTextForSelectedFile{"))
    }
}

private struct FilesCopyTextFixture {
    let viewModel: IngestionViewModel
    let store: IngestionStore
}

@MainActor
private func makeFixture(
    items: [IngestionListItem],
    api: FilesCopyTextAPI? = nil
) -> FilesCopyTextFixture {
    let resolvedAPI = api ?? FilesCopyTextAPI(
        metaByFileId: [:],
        contentByFileIdAndKind: [:],
        recorder: IngestionRequestRecorder()
    )
    let defaults = UserDefaults(suiteName: "FilesCopyTextTests.\(UUID().uuidString)")!
    let store = IngestionStore(api: resolvedAPI, cache: TestCacheClient(), userDefaults: defaults)
    store.applyListUpdate(items, persist: false)
    let viewModel = IngestionViewModel(
        api: resolvedAPI,
        store: store,
        temporaryStore: .shared,
        uploadManager: FilesCopyTextUploadManager(),
        toastCenter: ToastCenter()
    )
    return FilesCopyTextFixture(viewModel: viewModel, store: store)
}

private func makeItem(
    id: String,
    mimeType: String,
    recommendedViewer: String?
) -> IngestionListItem {
    IngestionListItem(
        file: makeFile(id: id, mimeType: mimeType),
        job: IngestionJob(
            status: "ready",
            stage: "ready",
            errorCode: nil,
            errorMessage: nil,
            userMessage: nil,
            progress: nil,
            attempts: 0,
            updatedAt: "2026-04-12T12:00:00Z"
        ),
        recommendedViewer: recommendedViewer
    )
}

private func makeFile(
    id: String,
    mimeType: String,
    filename: String? = nil
) -> IngestedFileMeta {
    IngestedFileMeta(
        id: id,
        filenameOriginal: filename ?? "\(id).txt",
        path: "/\(filename ?? "\(id).txt")",
        mimeOriginal: mimeType,
        sizeBytes: 32,
        sha256: nil,
        pinned: false,
        pinnedOrder: nil,
        category: nil,
        sourceUrl: nil,
        sourceMetadata: nil,
        createdAt: "2026-04-12T12:00:00Z",
        updatedAt: "2026-04-12T12:00:00Z",
        deletedAt: nil
    )
}

private func makeMeta(
    file: IngestedFileMeta,
    derivatives: [IngestionDerivative],
    recommendedViewer: String?
) -> IngestionMetaResponse {
    IngestionMetaResponse(
        file: file,
        job: IngestionJob(
            status: "ready",
            stage: "ready",
            errorCode: nil,
            errorMessage: nil,
            userMessage: nil,
            progress: nil,
            attempts: 0,
            updatedAt: "2026-04-12T12:00:00Z"
        ),
        derivatives: derivatives,
        recommendedViewer: recommendedViewer
    )
}

private func makeDerivative(kind: String, mimeType: String) -> IngestionDerivative {
    IngestionDerivative(
        id: "\(kind)-id",
        kind: kind,
        storageKey: "storage/\(kind)",
        mime: mimeType,
        sizeBytes: 32
    )
}

private func filesSource(
    named fileName: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let baseURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
    let sourceURL = (fileName == "FilesHeaderActions.swift"
        ? baseURL.appendingPathComponent("Files")
        : baseURL.appendingPathComponent("SidebarPanels"))
        .appendingPathComponent(fileName)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(fileName): \(error)", file: file, line: line)
        throw error
    }
}

private actor IngestionRequestRecorder {
    private var metaRequestLog: [String] = []
    private var contentRequestLog: [CopyContentRequest] = []

    func recordMeta(fileId: String) {
        metaRequestLog.append(fileId)
    }

    func recordContent(fileId: String, kind: String) {
        contentRequestLog.append(CopyContentRequest(fileId: fileId, kind: kind))
    }

    func metaRequests() -> [String] {
        metaRequestLog
    }

    func contentRequests() -> [CopyContentRequest] {
        contentRequestLog
    }
}

private struct CopyContentRequest: Equatable {
    let fileId: String
    let kind: String
}

private struct FilesCopyTextAPI: IngestionProviding {
    let metaByFileId: [String: IngestionMetaResponse]
    let contentByFileIdAndKind: [String: [String: Data]]
    let recorder: IngestionRequestRecorder

    func list() async throws -> IngestionListResponse {
        IngestionListResponse(items: [])
    }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        await recorder.recordMeta(fileId: fileId)
        guard let meta = metaByFileId[fileId] else {
            throw FilesCopyTextError.forced
        }
        return meta
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = range
        await recorder.recordContent(fileId: fileId, kind: kind)
        guard let data = contentByFileIdAndKind[fileId]?[kind] else {
            throw FilesCopyTextError.forced
        }
        return data
    }

    func upload(fileURL: URL, filename: String, mimeType: String, folder: String) async throws -> String {
        _ = fileURL
        _ = filename
        _ = mimeType
        _ = folder
        throw FilesCopyTextError.forced
    }

    func cancel(fileId: String) async throws {
        _ = fileId
        throw FilesCopyTextError.forced
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
        throw FilesCopyTextError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
        throw FilesCopyTextError.forced
    }

    func delete(fileId: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = clientUpdatedAt
        throw FilesCopyTextError.forced
    }

    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = filename
        _ = clientUpdatedAt
        throw FilesCopyTextError.forced
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        throw FilesCopyTextError.forced
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        return IngestionSyncResponse(applied: [], files: [], conflicts: [], updates: nil, serverUpdatedSince: nil)
    }
}

private enum FilesCopyTextError: Error {
    case forced
}

private final class FilesCopyTextUploadManager: IngestionUploadManaging {
    func startUpload(
        request: UploadRequest,
        onProgress: @escaping @Sendable (Double) -> Void,
        onCompletion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        _ = request
        _ = onProgress
        _ = onCompletion
    }

    func cancelUpload(uploadId: String) {
        _ = uploadId
    }
}

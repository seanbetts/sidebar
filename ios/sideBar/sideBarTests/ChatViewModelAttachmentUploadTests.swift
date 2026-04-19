import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
    func testAddAttachmentRejectsUnsupportedPlistBeforeNetworkUpload() async throws {
        let cache = TestCacheClient()
        let conversationsAPI = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        let ingestionAPI = makeIngestionAPIForAttachmentCancelTest { request in
            XCTFail("Unexpected upload request: \(request)")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            ingestionAPI: ingestionAPI,
            attachmentPollingInitialDelayNanoseconds: 0,
            attachmentPollingIntervalNanoseconds: 0
        )
        let plistURL = try makeTemporaryAttachmentURL(
            filename: "58692B3D-606D-4187-90EC-443CC61B301C.plist"
        )

        await viewModel.addAttachment(url: plistURL)

        XCTAssertEqual(viewModel.attachments.count, 1)
        XCTAssertEqual(viewModel.attachments.first?.status, .failed)
        XCTAssertEqual(viewModel.attachments.first?.stage, "failed")
        XCTAssertNil(viewModel.attachments.first?.fileId)
    }
}

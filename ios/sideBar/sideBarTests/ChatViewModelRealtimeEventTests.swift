import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelRealtimeEventTests: ChatViewModelTestCase {
    func testConversationTitleUpdatedEventRefreshesConversationTitleAndOrdering() async throws {
        let cache = TestCacheClient()
        let olderConversation = Conversation(
            id: "conv-1",
            title: "Old title",
            titleGenerated: true,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            messageCount: 1,
            firstMessage: "Hello",
            isArchived: nil
        )
        let newerConversation = Conversation(
            id: "conv-2",
            title: "Keep title",
            titleGenerated: false,
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 1,
            firstMessage: "Hello again",
            isArchived: nil
        )
        let detail = ConversationWithMessages(
            id: "conv-1",
            title: "Old title",
            titleGenerated: true,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            messageCount: 1,
            firstMessage: "Hello",
            isArchived: nil,
            messages: []
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        viewModel.chatStore.upsertConversation(olderConversation, persist: false)
        viewModel.chatStore.upsertConversation(newerConversation, persist: false)
        viewModel.chatStore.upsertConversationDetail(detail, persist: false)

        let payload =
            #"{"entity_type":"conversation","entity_id":"conv-1","change":"renamed","# +
            #""patch":{"title":"Renamed","titleGenerated":false,"updatedAt":"2026-04-19T12:00:00Z"},"# +
            #""invalidate":["conversations","conversation:conv-1"]}"#
        var parser = ChatStreamParser()
        let event = try XCTUnwrap(
            parser.ingest(
                Data(
                    """
                    event: entity_changed
                    data: \(payload)


                    """.utf8
                )
            ).first
        )

        viewModel.handle(event: event)

        XCTAssertEqual(
            viewModel.chatStore.conversations.first(where: { $0.id == "conv-1" })?.title,
            "Renamed"
        )
        XCTAssertEqual(viewModel.chatStore.conversationDetails["conv-1"]?.title, "Renamed")
        XCTAssertEqual(viewModel.groupedConversations.first?.conversations.first?.id, "conv-1")
        XCTAssertEqual(
            viewModel.conversationUpdatedAtDates["conv-1"],
            DateParsing.parseISO8601("2026-04-19T12:00:00Z")
        )
    }

    func testWebsiteRenamedEventInvalidatesWebsiteCaches() async throws {
        let cache = TestCacheClient()
        let item = WebsiteItem(
            id: "website-1",
            title: "Old title",
            url: "https://example.com/website-1",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-01-01T00:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
        let detail = WebsiteDetail(
            id: "website-1",
            title: "Old title",
            url: "https://example.com/website-1",
            urlFull: nil,
            domain: "example.com",
            content: "Body",
            source: nil,
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-01-01T00:00:00Z",
            lastOpenedAt: nil
        )
        cache.set(
            key: CacheKeys.websitesList,
            value: WebsitesResponse(items: [item], archivedCount: nil, archivedLastUpdated: nil),
            ttlSeconds: 60
        )
        cache.set(
            key: CacheKeys.websiteDetail(id: "website-1"),
            value: detail,
            ttlSeconds: 60
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )

        let payload =
            #"{"entity_type":"website","entity_id":"website-1","change":"renamed","# +
            #""patch":{"title":"Renamed website"},"invalidate":["websites","website:website-1"]}"#
        var parser = ChatStreamParser()
        let event = try XCTUnwrap(
            parser.ingest(
                Data(
                    """
                    event: entity_changed
                    data: \(payload)


                    """.utf8
                )
            ).first
        )

        viewModel.handle(event: event)

        let cachedList: WebsitesResponse? = cache.get(key: CacheKeys.websitesList)
        let cachedDetail: WebsiteDetail? = cache.get(
            key: CacheKeys.websiteDetail(id: "website-1")
        )
        XCTAssertNil(cachedList)
        XCTAssertNil(cachedDetail)
    }
}

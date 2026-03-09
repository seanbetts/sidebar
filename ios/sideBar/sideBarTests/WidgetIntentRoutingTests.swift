import AppIntents
import XCTest
@testable import sideBar

final class WidgetIntentRoutingTests: XCTestCase {
    func testAppWidgetIntentsReturnOpenResults() async throws {
        var quickSaveIntent = QuickSaveIntent()
        quickSaveIntent.url = URL(string: "https://example.com")!

        assertOpensIntent(try await AddTaskIntent().perform())
        assertOpensIntent(try await OpenTodayIntent().perform())
        assertOpensIntent(try await OpenNotesIntent().perform())
        assertOpensIntent(try await CreateNoteIntent().perform())
        assertOpensIntent(try await OpenWebsitesIntent().perform())
        assertOpensIntent(try await quickSaveIntent.perform())
        assertOpensIntent(try await OpenFilesIntent().perform())
        assertOpensIntent(try await OpenScratchpadIntent().perform())
        assertOpensIntent(try await StartChatIntent().perform())
    }
}

private func assertOpensIntent<Result: OpensIntent>(_: Result) {}

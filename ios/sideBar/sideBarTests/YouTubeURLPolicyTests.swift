import XCTest
@testable import sideBar

final class YouTubeURLPolicyTests: XCTestCase {
    func testExtractVideoIdSupportsNoCookieEmbedURL() {
        let raw = "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1"

        let videoId = YouTubeURLPolicy.extractVideoId(from: raw)

        XCTAssertEqual(videoId, "dQw4w9WgXcQ")
    }

    func testEmbedURLIncludesFullscreenParameter() {
        let embedURL = YouTubeURLPolicy.embedURL(videoId: "dQw4w9WgXcQ")

        XCTAssertEqual(
            embedURL?.absoluteString,
            "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ" +
                "?playsinline=1&rel=0&modestbranding=1&fs=1&origin=https://www.youtube-nocookie.com"
        )
    }

    func testPreferredExternalURLConvertsEmbedToWatchURL() {
        let embedURL = URL(string: "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ")!

        let preferred = YouTubeURLPolicy.preferredExternalURL(from: embedURL)

        XCTAssertEqual(preferred.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testPreferredExternalURLKeepsStandardWatchURLUnchanged() {
        let watchURL = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43s")!

        let preferred = YouTubeURLPolicy.preferredExternalURL(from: watchURL)

        XCTAssertEqual(preferred.absoluteString, watchURL.absoluteString)
    }
}

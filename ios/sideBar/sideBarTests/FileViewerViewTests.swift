import XCTest
@testable import sideBar

final class FileViewerViewTests: XCTestCase {
    func testShouldShowYouTubeEmbedFalseForVideoKind() {
        let state = FileViewerState(
            title: "video.mp4",
            kind: .video,
            text: nil,
            fileURL: nil,
            spreadsheet: nil,
            youtubeEmbedURL: URL(string: "https://www.youtube.com/embed/abc123xyzAA")
        )

        XCTAssertFalse(FileViewerView.shouldShowYouTubeEmbed(for: state))
    }

    func testShouldShowYouTubeEmbedTrueForTextKindWithEmbed() {
        let state = FileViewerState(
            title: "transcript.md",
            kind: .markdown,
            text: "content",
            fileURL: nil,
            spreadsheet: nil,
            youtubeEmbedURL: URL(string: "https://www.youtube.com/embed/abc123xyzAA")
        )

        XCTAssertTrue(FileViewerView.shouldShowYouTubeEmbed(for: state))
    }

    func testShouldShowYouTubeEmbedFalseWhenEmbedURLMissing() {
        let state = FileViewerState(
            title: "transcript.md",
            kind: .markdown,
            text: "content",
            fileURL: nil,
            spreadsheet: nil,
            youtubeEmbedURL: nil
        )

        XCTAssertFalse(FileViewerView.shouldShowYouTubeEmbed(for: state))
    }

    func testVideoTranscriptReturnsTrimmedTextForVideoKind() {
        let state = FileViewerState(
            title: "video.mp4",
            kind: .video,
            text: "\n\nTranscript line\n",
            fileURL: nil,
            spreadsheet: nil,
            youtubeEmbedURL: nil
        )

        XCTAssertEqual(FileViewerView.videoTranscript(for: state), "Transcript line")
    }

    func testVideoTranscriptReturnsNilWhenEmptyOrNotVideo() {
        let videoState = FileViewerState(
            title: "video.mp4",
            kind: .video,
            text: "   ",
            fileURL: nil,
            spreadsheet: nil,
            youtubeEmbedURL: nil
        )
        let markdownState = FileViewerState(
            title: "notes.md",
            kind: .markdown,
            text: "Transcript line",
            fileURL: nil,
            spreadsheet: nil,
            youtubeEmbedURL: nil
        )

        XCTAssertNil(FileViewerView.videoTranscript(for: videoState))
        XCTAssertNil(FileViewerView.videoTranscript(for: markdownState))
    }
}

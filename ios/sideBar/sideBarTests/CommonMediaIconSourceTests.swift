import XCTest

final class CommonMediaIconSourceTests: XCTestCase {
    func testAudioPlayerAndTikTokFallbackControlsRouteIconsThroughAppIcon() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
        let audioPlayer = try normalizedSource(at: ["sideBar", "Views", "Common", "AudioPlayerView.swift"])
        let tikTokFallback = try normalizedSource(at: [
            "sideBar", "Views", "Common", "SideBarMarkdown+TikTok.swift"
        ])

        XCTAssertTrue(appIcon.contains("publicstaticletplayControl=AppIcon(rawValue:\"play.fill\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletpauseControl=AppIcon(rawValue:\"pause.fill\")"))

        XCTAssertTrue(audioPlayer.contains("importsideBarShared"))
        XCTAssertTrue(
            audioPlayer.contains(
                "Image(appIcon:viewModel.isPlaying?AppIcon.Media.pauseControl:AppIcon.Media.playControl)"
            )
        )
        XCTAssertFalse(audioPlayer.contains("\"play.fill\""))
        XCTAssertFalse(audioPlayer.contains("\"pause.fill\""))

        XCTAssertTrue(tikTokFallback.contains("importsideBarShared"))
        XCTAssertTrue(tikTokFallback.contains("Image(appIcon:AppIcon.Media.playFilled)"))
        XCTAssertFalse(tikTokFallback.contains("Image(systemName:\"play.circle.fill\")"))
    }

    private func normalizedSource(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let source = try source(at: pathComponents, file: file, line: line)
        return source.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func source(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = pathComponents.reduce(sideBarRoot) { url, component in
            url.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}

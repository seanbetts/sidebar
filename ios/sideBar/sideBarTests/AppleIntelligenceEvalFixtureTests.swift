import XCTest
@testable import sideBar

final class AppleIntelligenceEvalFixtureTests: XCTestCase {
    func testRouteMetadataFixtureDecodesWithoutSensitiveText() throws {
        let fixtureURL = routeMetadataFixtureURL()
        let data = try Data(contentsOf: fixtureURL)

        let metadata = try JSONDecoder().decode(IntelligenceRouteMetadata.self, from: data)

        XCTAssertEqual(metadata.descriptor.capability, .liveNotes)
        XCTAssertEqual(metadata.descriptor.executionRoute, .appleOnDevice)
        XCTAssertNil(metadata.extra["prompt"])
        XCTAssertNil(metadata.extra["transcript_text"])
        XCTAssertEqual(metadata.extra["fixture_id"], "route-metadata-sample")
    }

    private func routeMetadataFixtureURL() -> URL {
        let relativePath = "docs/evals/apple-intelligence/fixtures/route-metadata-sample.json"
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidates = [
            currentDirectoryURL.appendingPathComponent(relativePath),
            sourceRootURL.appendingPathComponent(relativePath)
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }
}

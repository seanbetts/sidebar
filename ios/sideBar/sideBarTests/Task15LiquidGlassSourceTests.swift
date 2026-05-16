import XCTest

final class Task15LiquidGlassSourceTests: XCTestCase {
    func testSharedGlassChromeDefinesLargeFeatureCardKinds() throws {
        let source = try normalizedSource(at: ["sideBar", "Design", "Styles", "GlassChrome.swift"])

        XCTAssertTrue(source.contains("caselargeCard"))
        XCTAssertTrue(source.contains("caseextraLargeCard"))
        XCTAssertTrue(source.contains(".largeCard:Tokens("))
        XCTAssertTrue(source.contains(".extraLargeCard:Tokens("))
    }

    func testFeatureDiscoveryCarouselUsesSharedGlassChrome() throws {
        let source = try normalizedSource(at: ["sideBar", "Views", "Chat", "StaticFeatureCarousel.swift"])

        XCTAssertTrue(source.contains(".glassChrome(.extraLargeCard)"))
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: ".glassChrome(.pill)").count - 1,
            1
        )
        XCTAssertFalse(source.contains(".glassEffect("))
        XCTAssertFalse(source.contains(".ultraThinMaterial"))
    }

    func testFeatureIntroCardUsesSharedGlassChrome() throws {
        let source = try normalizedSource(at: ["sideBar", "Views", "Chat", "FeatureIntroCard.swift"])

        XCTAssertTrue(source.contains(".glassChrome(.largeCard)"))
        XCTAssertFalse(source.contains(".glassEffect("))
        XCTAssertFalse(source.contains(".ultraThinMaterial"))
    }

    func testWebsiteQuickActionsUseSharedGlassChrome() throws {
        let source = try normalizedSource(at: ["sideBar", "Views", "Websites", "WebsitesDetailView+MenuActions.swift"])

        XCTAssertTrue(source.contains(".glassChrome(.pill)"))
        XCTAssertFalse(source.contains(".glassEffect("))
    }

    func testSoulCalibrationChoiceChipsUseSharedGlassChrome() throws {
        let source = try normalizedSource(at: ["sideBar", "Views", "Chat", "SoulCalibrationPromptComponents.swift"])

        XCTAssertTrue(source.contains(".glassChrome(.pill)"))
        XCTAssertFalse(source.contains(".glassEffect("))
    }

    private func normalizedSource(
        at components: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = components.reduce(sideBarRoot) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}

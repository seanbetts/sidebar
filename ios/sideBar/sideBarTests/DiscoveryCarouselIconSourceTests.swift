import XCTest

final class DiscoveryCarouselIconSourceTests: XCTestCase {
    func testStaticDiscoveryCarouselUsesAppIconVocabulary() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
        let carousel = try normalizedSource(at: ["sideBar", "Views", "Chat", "StaticFeatureCarousel.swift"])

        XCTAssertTrue(appIcon.contains("publicstaticletfeatureDiscovery=AppIcon(rawValue:\"sparkles.rectangle.stack\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletchevronUp=AppIcon(rawValue:\"chevron.up\")"))

        XCTAssertTrue(carousel.contains("Image(appIcon:AppIcon.Onboarding.featureDiscovery)"))
        XCTAssertTrue(carousel.contains("Image(appIcon:isExpanded?AppIcon.Navigation.chevronUp:AppIcon.Navigation.chevronDown)"))
        XCTAssertTrue(carousel.contains("Image(appIcon:AppIcon.Action.close)"))
        XCTAssertFalse(carousel.contains("Image(systemName:\"sparkles.rectangle.stack\")"))
        XCTAssertFalse(carousel.contains("Image(systemName:isExpanded?\"chevron.up\":\"chevron.down\")"))
        XCTAssertFalse(carousel.contains("Image(systemName:\"xmark\")"))
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

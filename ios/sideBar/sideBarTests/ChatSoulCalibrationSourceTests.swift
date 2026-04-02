import XCTest

final class ChatSoulCalibrationSourceTests: XCTestCase {
    func testSoulCalibrationPromptViewIncludesPrimaryGoalChoices() throws {
        let normalized = try combinedCalibrationSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Whatwouldyoumostlikemetohelpwithfirst?"))
        XCTAssertTrue(normalized.contains("Personalproductivity"))
        XCTAssertTrue(normalized.contains("Workproductivity"))
        XCTAssertTrue(normalized.contains("Planningandtasks"))
        XCTAssertTrue(normalized.contains("Notesandideas"))
        XCTAssertTrue(normalized.contains("Lifeadmin"))
        XCTAssertTrue(normalized.contains("Learningandresearch"))
        XCTAssertTrue(normalized.contains("AIcompanion"))
    }

    func testSoulCalibrationPromptViewIncludesWorkingRelationshipChoices() throws {
        let normalized = try combinedCalibrationSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Howwouldyoulikemetoworkwithyou?"))
        XCTAssertTrue(normalized.contains("JusthelpwhenIask"))
        XCTAssertTrue(normalized.contains("Keepmeontrack"))
        XCTAssertTrue(normalized.contains("Takeinitiativewithme"))
    }

    func testSoulCalibrationPromptViewIncludesTonePairsAndNameActions() throws {
        let normalized = try combinedCalibrationSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("HowshouldIshowup?"))
        XCTAssertTrue(normalized.contains("Warm"))
        XCTAssertTrue(normalized.contains("Direct"))
        XCTAssertTrue(normalized.contains("Playful"))
        XCTAssertTrue(normalized.contains("Serious"))
        XCTAssertTrue(normalized.contains("Concise"))
        XCTAssertTrue(normalized.contains("Expressive"))
        XCTAssertTrue(normalized.contains("Formal"))
        XCTAssertTrue(normalized.contains("Casual"))
        XCTAssertTrue(normalized.contains("Supportive"))
        XCTAssertTrue(normalized.contains("Challenging"))
        XCTAssertTrue(normalized.contains("Looksgood"))
        XCTAssertTrue(normalized.contains("Tryanother"))
    }

    func testChatViewEmbedsSoulCalibrationPromptView() throws {
        let normalized = try combinedCalibrationSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SoulCalibrationPromptView("))
    }

    private func combinedCalibrationSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewsRoot = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
        let sourceURLs = [
            viewsRoot.appendingPathComponent("Chat").appendingPathComponent("ChatView.swift"),
            viewsRoot.appendingPathComponent("Chat").appendingPathComponent("SoulCalibrationPromptView.swift")
        ]

        do {
            return try sourceURLs
                .map { try String(contentsOf: $0, encoding: .utf8) }
                .joined(separator: "\n")
        } catch {
            XCTFail("Failed to read chat soul calibration sources: \(error)", file: file, line: line)
            throw error
        }
    }
}

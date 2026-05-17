import XCTest

final class AppIconSourceGuardTests: XCTestCase {
    func testProductionSwiftDoesNotIntroduceRawAppOwnedSystemSymbolLiterals() throws {
        let root = sideBarRootURL()
        let files = try productionSwiftFiles(under: root)
        var violations: [String] = []

        for file in files where !isAllowedRawSymbolFile(file, root: root) {
            let source = try String(contentsOf: file, encoding: .utf8)
            violations.append(contentsOf: rawSystemSymbolViolations(in: source, file: file, root: root))
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Raw SF Symbol literals must use AppIcon or an approved dynamic boundary:\n"
                + violations.joined(separator: "\n")
        )
    }

    func testRawSymbolGuardCatchesMultilineSystemSymbolLiterals() {
        let root = URL(fileURLWithPath: "/tmp/sideBar")
        let file = root.appendingPathComponent("sideBar/Views/ExampleView.swift")
        let source = """
        import SwiftUI

        struct ExampleView: View {
            var body: some View {
                Image(
                    systemName:
                        "trash"
                )
            }
        }
        """

        XCTAssertFalse(rawSystemSymbolViolations(in: source, file: file, root: root).isEmpty)
    }

    private func productionSwiftFiles(under root: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            guard url.pathExtension == "swift" else { return nil }
            let path = url.path
            guard !path.contains("/Vendor/") else { return nil }
            guard !path.contains("/sideBarTests/") else { return nil }
            guard !path.contains("/sideBarUITests/") else { return nil }
            guard !path.contains("/ShareExtensionTests/") else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }

    private func isAllowedRawSymbolFile(_ file: URL, root: URL) -> Bool {
        let relativePath = file.path.replacingOccurrences(of: root.path + "/", with: "")
        return relativePath == "sideBarShared/Utilities/AppIcon.swift"
    }

    private func rawSystemSymbolViolations(in source: String, file: URL, root: URL) -> [String] {
        let patterns = [
            #"Image\s*\(\s*systemName\s*:\s*""#,
            #"Label\s*\([\s\S]*?\bsystemImage\s*:\s*""#,
            #"UIImage\s*\(\s*systemName\s*:\s*""#,
            #"NSImage\s*\(\s*systemSymbolName\s*:\s*""#,
            #"\bsystemName\s*:\s*""#,
            #"\bsystemImage\s*:\s*""#,
            #"\bsystemSymbolName\s*:\s*""#,
            #"\bsystemImageName\s*:\s*""#,
            #"\bAppIcon\s*\(\s*rawValue\s*:\s*""#
        ]
        let relativePath = file.path.replacingOccurrences(of: root.path + "/", with: "")
        return patterns.flatMap { pattern in
            source.ranges(matchingRegularExpression: pattern).map { match in
                let lineNumber = source.lineNumber(at: match.lowerBound)
                let preview = String(source[match])
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(relativePath):\(lineNumber): \(preview)"
            }
        }
    }
}

private extension String {
    func ranges(matchingRegularExpression pattern: String) -> [Range<String.Index>] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        return expression.matches(in: self, range: range).compactMap { match in
            Range(match.range, in: self)
        }
    }

    func lineNumber(at index: String.Index) -> Int {
        self[..<index].reduce(1) { lineNumber, character in
            character == "\n" ? lineNumber + 1 : lineNumber
        }
    }
}

private extension XCTestCase {
    func sideBarRootURL(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

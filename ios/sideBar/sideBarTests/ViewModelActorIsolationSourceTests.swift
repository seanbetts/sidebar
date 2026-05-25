import XCTest

final class ViewModelActorIsolationSourceTests: XCTestCase {
    func testStaleTaskProviderCompatibilityAliasIsAbsent() throws {
        let sourceRoot = try sideBarSourceRoot()
        let taskProviderURL = sourceRoot.appendingPathComponent("ViewModels/TaskProvider.swift")

        XCTAssertFalse(FileManager.default.fileExists(atPath: taskProviderURL.path))
    }

    func testPublicViewModelsKeepMainActorOnDeclarationLine() throws {
        let sourceRoot = try sideBarSourceRoot()
        let viewModels = [
            ("SettingsViewModel.swift", "SettingsViewModel"),
            ("IngestionViewModel.swift", "IngestionViewModel"),
            ("WebsitesViewModel.swift", "WebsitesViewModel"),
            ("NotesViewModel.swift", "NotesViewModel"),
            ("NotesEditorViewModel.swift", "NotesEditorViewModel"),
            ("NativeNoteEditorViewModel.swift", "NativeNoteEditorViewModel"),
            ("TasksViewModel.swift", "TasksViewModel"),
            ("OnboardingViewModel.swift", "OnboardingViewModel"),
            ("CurrentLocationViewModel.swift", "CurrentLocationViewModel"),
            ("ScratchpadViewModel.swift", "ScratchpadViewModel"),
            ("MemoriesViewModel.swift", "MemoriesViewModel"),
            ("PlacesViewModel.swift", "PlacesViewModel"),
            ("WeatherViewModel.swift", "WeatherViewModel"),
            ("InternalNotificationDiagnosticsViewModel.swift", "InternalNotificationDiagnosticsViewModel")
        ]

        for (relativePath, typeName) in viewModels {
            let source = try sourceText(in: sourceRoot, relativePath: "ViewModels/\(relativePath)")
            let normalized = source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

            XCTAssertTrue(
                normalized.contains("@MainActor public final class \(typeName)"),
                "\(typeName) should keep @MainActor on the public class declaration line."
            )
            XCTAssertFalse(
                source.contains("@MainActor\n///"),
                "\(typeName) should keep its doc comment immediately above the declaration attributes."
            )
        }
    }

    func testPublicAppServiceAndUtilityTypesKeepMainActorOnDeclarationLine() throws {
        let sourceRoot = try sideBarSourceRoot()
        let folders = ["App", "Services", "Utilities"]
        let violations = try folders.flatMap { folder in
            try publicMainActorDeclarationViolations(
                in: sourceRoot.appendingPathComponent(folder),
                sourceRoot: sourceRoot
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Public @MainActor declarations should place @MainActor on the declaration line:\n"
                + violations.joined(separator: "\n")
        )
    }
}

private func sideBarSourceRoot(file: StaticString = #filePath) throws -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
}

private func sourceText(in sourceRoot: URL, relativePath: String) throws -> String {
    try String(contentsOf: sourceRoot.appendingPathComponent(relativePath), encoding: .utf8)
}

private func publicMainActorDeclarationViolations(
    in folder: URL,
    sourceRoot: URL
) throws -> [String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: folder,
        includingPropertiesForKeys: nil
    ) else {
        return []
    }

    var violations: [String] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces) == "@MainActor" {
            var declarationIndex = index + 1
            while declarationIndex < lines.count {
                let nextLine = lines[declarationIndex].trimmingCharacters(in: .whitespaces)
                if nextLine.isEmpty || nextLine.hasPrefix("///") {
                    declarationIndex += 1
                    continue
                }
                if nextLine.hasPrefix("public ") {
                    let relativePath = fileURL.path.replacingOccurrences(
                        of: sourceRoot.path + "/",
                        with: ""
                    )
                    violations.append("\(relativePath):\(index + 1) -> \(nextLine)")
                }
                break
            }
        }
    }
    return violations.sorted()
}

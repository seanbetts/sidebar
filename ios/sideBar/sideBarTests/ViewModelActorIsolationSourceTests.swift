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

import Foundation

enum TestIsolation {
    struct IsolatedUserDefaults {
        let suiteName: String
        let defaults: UserDefaults

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    struct IsolatedTemporaryDirectory {
        let url: URL

        func tearDown() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func makeUserDefaults(prefix: String) -> IsolatedUserDefaults {
        let suiteName = "\(prefix).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to create isolated UserDefaults suite \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return IsolatedUserDefaults(suiteName: suiteName, defaults: defaults)
    }

    static func makeTemporaryDirectory(prefix: String) throws -> IsolatedTemporaryDirectory {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix).\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return IsolatedTemporaryDirectory(url: directoryURL)
    }
}

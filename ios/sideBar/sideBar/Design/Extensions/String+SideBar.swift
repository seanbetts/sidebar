import Foundation

extension String {
    var trimmedSideBar: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func withoutFileExtension() -> String {
        stripFileExtension(self)
    }
}

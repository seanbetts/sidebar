import Foundation

extension String {
    var trimmedSideBar: String {
        trimmed
    }

    func withoutFileExtension() -> String {
        stripFileExtension(self)
    }
}

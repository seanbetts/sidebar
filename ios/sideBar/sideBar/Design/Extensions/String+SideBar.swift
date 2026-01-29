import Foundation
import sideBarShared

extension String {
    var trimmedSideBar: String {
        trimmed
    }

    func withoutFileExtension() -> String {
        stripFileExtension(self)
    }
}

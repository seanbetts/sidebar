import Foundation

enum MenuActionScheduler {
    @MainActor
    static func perform(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }
}

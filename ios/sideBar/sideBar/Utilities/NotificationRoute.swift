import Foundation

enum NotificationRoute: Equatable {
    case deepLink(URL)

    init?(userInfo: [AnyHashable: Any]) {
        let routeString = (userInfo["sidebar_route"] as? String)
            ?? (userInfo["route"] as? String)
        guard let routeString,
              let url = URL(string: routeString),
              url.scheme == "sidebar" else {
            return nil
        }
        self = .deepLink(url)
    }

    var url: URL {
        switch self {
        case .deepLink(let url):
            return url
        }
    }
}

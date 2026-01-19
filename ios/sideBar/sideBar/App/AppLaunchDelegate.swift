import Foundation
import os

#if os(iOS)
import UIKit

final class AppLaunchDelegate: NSObject, UIApplicationDelegate {
    override init() {
        super.init()
        #if DEBUG
        AppLaunchMetrics.shared.mark("AppLaunchDelegate init")
        #endif
    }

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        AppLaunchMetrics.shared.mark("willFinishLaunching")
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        AppLaunchMetrics.shared.mark("didFinishLaunching")
        #endif
        return true
    }
}
#endif

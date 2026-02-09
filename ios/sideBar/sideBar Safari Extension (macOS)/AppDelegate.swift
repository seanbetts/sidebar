//
//  AppDelegate.swift
//  sideBar Safari Extension (macOS)
//
//  Created by Sean Betts on 01/02/2026.
//

#if canImport(AppKit)
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
}
#else
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        _ = launchOptions
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        _ = application
        _ = options
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
#endif

//
//  SceneDelegate.swift
//  sideBar Safari Extension (macOS)
//
//  Created by Sean Betts on 01/02/2026.
//

#if canImport(UIKit)
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        _ = session
        _ = connectionOptions
        guard scene is UIWindowScene else { return }
    }
}
#endif

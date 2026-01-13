//
//  sideBarApp.swift
//  sideBar
//
//  Created by Sean Betts on 08/01/2026.
//

import SwiftUI

@main
struct sideBarApp: App {
    @StateObject private var environment: AppEnvironment

    init() {
        let config: EnvironmentConfig
        let configError: EnvironmentConfigLoadError?
        do {
            config = try EnvironmentConfig.load()
            configError = nil
        } catch {
            if EnvironmentConfig.isRunningTestsOrPreviews() {
                config = EnvironmentConfig.fallbackForTesting()
                configError = nil
            } else {
                config = EnvironmentConfig.fallbackForTesting()
                configError = error as? EnvironmentConfigLoadError
            }
        }

        let authSession = SupabaseAuthAdapter(
            config: config,
            stateStore: KeychainAuthStateStore()
        )

        let cacheClient = CoreDataCacheClient(container: PersistenceController.shared.container)
        let container = ServiceContainer(config: config, authSession: authSession, cacheClient: cacheClient)
        _environment = StateObject(wrappedValue: AppEnvironment(container: container, configError: configError))
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ContentView()
                .environmentObject(environment)
                .environment(\.controlSize, .large)
                .dynamicTypeSize(.large)
            #else
            ContentView()
                .environmentObject(environment)
            #endif
        }
        #if os(macOS)
        .commands {
            SidebarCommands()
        }
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(environment)
        }
        #endif
    }
}

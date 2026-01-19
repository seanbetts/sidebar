//
//  sideBarApp.swift
//  sideBar
//
//  Created by Sean Betts on 08/01/2026.
//

import SwiftUI
import os

@main
struct sideBarApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppLaunchDelegate.self) private var appDelegate
    #endif
    @StateObject private var environment: AppEnvironment

    init() {
        let launchStart = CFAbsoluteTimeGetCurrent()
        let logger = Logger(subsystem: "sideBar", category: "Startup")
        let logStep: (String, Double, Double) -> Void = { name, start, end in
            let elapsedMs = Int((end - start) * 1000)
            logger.info("\(name, privacy: .public) took \(elapsedMs, privacy: .public)ms")
        }

        let config: EnvironmentConfig
        let configError: EnvironmentConfigLoadError?
        let configStart = CFAbsoluteTimeGetCurrent()
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
        let configEnd = CFAbsoluteTimeGetCurrent()
        logStep("Config load", configStart, configEnd)

        let authStart = CFAbsoluteTimeGetCurrent()
        let authSession = SupabaseAuthAdapter(
            config: config,
            stateStore: KeychainAuthStateStore(
                service: AppGroupConfiguration.keychainService,
                accessGroup: AppGroupConfiguration.keychainAccessGroup
            )
        )
        let authEnd = CFAbsoluteTimeGetCurrent()
        logStep("Auth session", authStart, authEnd)

        let cacheStart = CFAbsoluteTimeGetCurrent()
        let cacheClient = CoreDataCacheClient(container: PersistenceController.shared.container)
        let container = ServiceContainer(config: config, authSession: authSession, cacheClient: cacheClient)
        let cacheEnd = CFAbsoluteTimeGetCurrent()
        logStep("Service container", cacheStart, cacheEnd)

        let envStart = CFAbsoluteTimeGetCurrent()
        _environment = StateObject(wrappedValue: AppEnvironment(container: container, configError: configError))
        let envEnd = CFAbsoluteTimeGetCurrent()
        logStep("Environment", envStart, envEnd)

        let launchEnd = CFAbsoluteTimeGetCurrent()
        logStep("Startup total", launchStart, launchEnd)
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

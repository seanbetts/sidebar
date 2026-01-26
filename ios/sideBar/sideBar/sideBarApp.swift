//
//  sideBarApp.swift
//  sideBar
//
//  Created by Sean Betts on 08/01/2026.
//

import AppIntents
import Foundation
import SwiftUI
import os

@main
struct SideBarApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppLaunchDelegate.self) private var appDelegate
    #endif
    @StateObject private var environment: AppEnvironment

    init() {
        let isTestMode = EnvironmentConfig.isRunningTestsOrPreviews()
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
            if isTestMode {
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
        let stateStore: AuthStateStore = isTestMode
            ? InMemoryAuthStateStore()
            : KeychainAuthStateStore(
                service: AppGroupConfiguration.keychainService,
                accessGroup: AppGroupConfiguration.keychainAccessGroup
            )
        let authSession = SupabaseAuthAdapter(
            config: config,
            stateStore: stateStore,
            startAuthStateTask: !isTestMode
        )
        let authEnd = CFAbsoluteTimeGetCurrent()
        logStep("Auth session", authStart, authEnd)

        let cacheStart = CFAbsoluteTimeGetCurrent()
        let cacheClient: CacheClient = isTestMode
            ? InMemoryCacheClient()
            : CoreDataCacheClient(container: PersistenceController.shared.container)
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
                .onOpenURL { url in
                    environment.handleDeepLink(url)
                }
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

// MARK: - Widget Intents (App Process)

/// App-target copy so openAppWhenRun executes in the app process and logs here.
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Opens sideBar to add a new task")
    static var openAppWhenRun: Bool = true
    private let logger = Logger(subsystem: "sideBar", category: "WidgetIntent")

    func perform() async throws -> some IntentResult {
        logger.info("AddTaskIntent recording pending add task (app process)")
        WidgetDataManager.shared.recordAddTaskIntent()
        return .result()
    }
}

struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"
    static var description = IntentDescription("Opens sideBar to Today's tasks")
    static var openAppWhenRun: Bool = true
    private let logger = Logger(subsystem: "sideBar", category: "WidgetIntent")

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://tasks/today") else {
            logger.error("OpenTodayIntent failed: invalid deep link URL")
            return .result()
        }
        logger.info("OpenTodayIntent opening deep link (app process)")
        return .result(opensIntent: OpenURLIntent(url))
    }
}

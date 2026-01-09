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
        do {
            config = try EnvironmentConfig.load()
        } catch {
            preconditionFailure("Failed to load app configuration: \(error)")
        }

        let authSession = SupabaseAuthAdapter(
            config: config,
            stateStore: InMemoryAuthStateStore()
        )

        let cacheClient = CoreDataCacheClient(container: PersistenceController.shared.container)
        let container = ServiceContainer(config: config, authSession: authSession, cacheClient: cacheClient)
        _environment = StateObject(wrappedValue: AppEnvironment(container: container))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
        }
    }
}

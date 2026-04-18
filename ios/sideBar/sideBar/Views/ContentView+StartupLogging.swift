import OSLog

extension ContentView {
    func logStartup(_ message: String) {
        #if DEBUG
        #if os(iOS)
        AppLaunchMetrics.shared.mark(message)
        #else
        let logger = Logger(subsystem: "sideBar", category: "Startup")
        logger.info("\(message, privacy: .public)")
        #endif
        #endif
    }
}

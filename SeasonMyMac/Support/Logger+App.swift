import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "SeasonMyMac"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let rendering = Logger(subsystem: subsystem, category: "Rendering")
}

import OSLog

enum Log {
    static let subsystem = "com.fitcheck"

    static let hardware = Logger(subsystem: subsystem, category: "hardware")
    static let catalog = Logger(subsystem: subsystem, category: "catalog")
    static let compatibility = Logger(subsystem: subsystem, category: "compatibility")
    static let providers = Logger(subsystem: subsystem, category: "providers")
    static let api = Logger(subsystem: subsystem, category: "api")
}

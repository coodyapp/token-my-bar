#if canImport(os)
import os

/// Shared unified-logging handles. Subsystem groups TokenMyBar entries in
/// Console.app; categories isolate areas for filtering. Never log secrets —
/// only counts, provider ids, statuses, and HTTP codes go through here.
public enum Log {
    private static let subsystem = "app.tokenmybar"
    public static let refresh = Logger(subsystem: subsystem, category: "refresh")
    public static let provider = Logger(subsystem: subsystem, category: "provider")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
#else
/// No-op logging shim for platforms without Apple's unified logging (e.g. the
/// Linux/Waybar build). Call sites are identical to the `os` implementation.
public enum Log {
    public struct Logger {
        public func debug(_ message: @autoclosure () -> String) {}
        public func info(_ message: @autoclosure () -> String) {}
        public func notice(_ message: @autoclosure () -> String) {}
        public func error(_ message: @autoclosure () -> String) {}
    }
    public static let refresh = Logger()
    public static let provider = Logger()
    public static let app = Logger()
}
#endif

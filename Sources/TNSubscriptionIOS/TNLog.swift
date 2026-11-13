import Foundation
import RevenueCat

// MARK: - TNLogLevel

/// Severity levels for TNSubscriptionIOS diagnostics.
/// (Các mức độ log cho TNSubscriptionIOS.)
///
/// Levels are ordered: a message is emitted only when its level is **at or above**
/// the configured threshold. `.none` disables logging entirely.
///
/// ```swift
/// TNSubscriptionIOS.logLevel = .verbose   // see everything, including RevenueCat SDK logs
/// TNSubscriptionIOS.logLevel = .none      // silence
/// ```
public enum TNLogLevel: Int, Comparable, CustomStringConvertible, Sendable {
    /// Every internal step, including each StoreKit transaction inspected.
    case verbose = 0
    /// Resolution details useful while debugging entitlement problems.
    case debug = 1
    /// Lifecycle milestones: configuration, unlocks, purchases, restores.
    case info = 2
    /// Misconfiguration and recoverable fallbacks.
    case warn = 3
    /// Failures only.
    case error = 4
    /// Logging disabled.
    case none = 5

    public static func < (lhs: TNLogLevel, rhs: TNLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        case .none: return "NONE"
        }
    }

    /// `.info` in `DEBUG` builds, `.error` in Release builds.
    /// (`.info` khi build DEBUG, `.error` khi build Release.)
    public static var `default`: TNLogLevel {
        #if DEBUG
        return .info
        #else
        return .error
        #endif
    }

    /// The equivalent RevenueCat level, or `nil` when logging is disabled.
    var revenueCatLevel: RevenueCat.LogLevel? {
        switch self {
        case .verbose: return .verbose
        case .debug: return .debug
        case .info: return .info
        case .warn: return .warn
        case .error: return .error
        case .none: return nil
        }
    }

    /// Maps a RevenueCat level onto a `TNLogLevel`, so SDK logs can be forwarded
    /// to the host app's log handler.
    init(revenueCatLevel: RevenueCat.LogLevel) {
        switch revenueCatLevel {
        case .verbose: self = .verbose
        case .debug: self = .debug
        case .info: self = .info
        case .warn: self = .warn
        case .error: self = .error
        @unknown default: self = .info
        }
    }
}

// MARK: - TNLog

/// Internal logger. Routes messages to `TNSubscriptionIOS.logHandler` when the host app
/// installed one, otherwise to `print`.
///
/// Messages are passed as autoclosures, so string interpolation is never evaluated
/// for a message that the current threshold filters out.
enum TNLog {

    private static let lock = NSLock()
    private static var _level: TNLogLevel = .default
    private static var _handler: ((TNLogLevel, String) -> Void)?

    /// The current threshold. Messages below it are dropped.
    static var level: TNLogLevel {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _level
        }
        set {
            lock.lock()
            _level = newValue
            lock.unlock()
        }
    }

    /// The host app's log sink, if installed.
    static var handler: ((TNLogLevel, String) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _handler
        }
        set {
            lock.lock()
            _handler = newValue
            lock.unlock()
        }
    }

    /// Emits a message if `level` meets the current threshold.
    static func log(_ level: TNLogLevel, _ message: @autoclosure () -> String) {
        lock.lock()
        let threshold = _level
        let sink = _handler
        lock.unlock()

        guard threshold != .none, level >= threshold else { return }

        let text = message()
        if let sink = sink {
            sink(level, text)
        } else {
            print("[TNSubscriptionIOS][\(level)] \(text)")
        }
    }

    static func verbose(_ message: @autoclosure () -> String) { log(.verbose, message()) }
    static func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    static func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    static func warn(_ message: @autoclosure () -> String) { log(.warn, message()) }
    static func error(_ message: @autoclosure () -> String) { log(.error, message()) }
}

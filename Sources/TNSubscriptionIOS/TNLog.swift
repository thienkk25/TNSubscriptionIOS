import Foundation
import RevenueCat

// MARK: - TNLogLevel ↔ RevenueCat

// `TNLogLevel` itself lives in TNSubscriptionShared; only the RevenueCat mapping is engine-specific.
// (`TNLogLevel` nằm trong TNSubscriptionShared; chỉ phần map sang RevenueCat là riêng của engine.)
extension TNLogLevel {

    /// The equivalent RevenueCat level, or `nil` when logging is disabled.
    /// (Mức tương ứng của RevenueCat, hoặc `nil` khi tắt log.)
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

    /// Maps a RevenueCat level onto a `TNLogLevel`, so SDK logs reach the host app's handler.
    /// (Map một mức của RevenueCat sang `TNLogLevel`, để log của SDK tới được handler của app.)
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

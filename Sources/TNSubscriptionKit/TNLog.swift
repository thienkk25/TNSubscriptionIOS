import Foundation
import os

// MARK: - TNLog

/// The engines' internal logger. Routes messages to the engine's `logHandler` when the host app
/// installed one, otherwise to the unified logging system (`os.Logger`).
/// (Logger nội bộ của các engine. Gửi log tới `logHandler` của engine nếu app có gắn, nếu không thì
/// gửi vào unified logging (`os.Logger`).)
///
/// Messages are passed as autoclosures, so string interpolation is never evaluated for a message
/// that the current threshold filters out.
/// (Thông điệp được truyền dạng autoclosure, nên chuỗi nội suy không bao giờ bị tính toán nếu mức
/// log hiện tại đã lọc bỏ nó.)
///
/// An engine with a vendor SDK forwards the level to that SDK itself, in its own `logLevel` setter
/// (see `TNAdaptyLog.swift`); nothing vendor-specific lives here.
/// (Engine có SDK nhà cung cấp tự chuyển mức log sang SDK đó trong setter `logLevel` của mình — xem
/// `TNAdaptyLog.swift`; ở đây không có gì riêng của nhà cung cấp.)
package enum TNLog {

    private static let lock = NSLock()
    private static var _level: TNLogLevel = .default
    private static var _handler: ((TNLogLevel, String) -> Void)?
    private static var _logger = makeLogger(category: "TNSubscription")

    private static func makeLogger(category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.tnsubscription", category: category)
    }

    /// Names the engine in Console.app. Called once by each engine's `configure`.
    /// (Đặt tên engine hiển thị trong Console.app. Mỗi engine gọi một lần trong `configure`.)
    package static func setCategory(_ category: String) {
        let logger = makeLogger(category: category)
        lock.lock()
        _logger = logger
        lock.unlock()
    }

    /// The current threshold. (Ngưỡng hiện tại.)
    package static var level: TNLogLevel {
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

    /// The host app's log sink, if installed. (Nơi nhận log của app, nếu đã gắn.)
    package static var handler: ((TNLogLevel, String) -> Void)? {
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
    /// (Phát ra thông điệp nếu `level` đạt ngưỡng hiện tại.)
    package static func log(_ level: TNLogLevel, _ message: @autoclosure () -> String) {
        lock.lock()
        let threshold = _level
        let sink = _handler
        let logger = _logger
        lock.unlock()

        guard threshold != .none, level >= threshold else { return }

        let text = message()
        if let sink {
            sink(level, text)
        } else {
            logger.log(level: level.osLogType, "[\(level.description, privacy: .public)] \(text, privacy: .public)")
        }
    }

    package static func verbose(_ message: @autoclosure () -> String) { log(.verbose, message()) }
    package static func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    package static func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    package static func warn(_ message: @autoclosure () -> String) { log(.warn, message()) }
    package static func error(_ message: @autoclosure () -> String) { log(.error, message()) }
}

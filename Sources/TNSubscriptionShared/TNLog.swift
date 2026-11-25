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
/// Every engine uses this one logger, the RevenueCat engine included. An engine with a vendor SDK
/// forwards the level to that SDK itself (see `TNAdaptyLog.swift`, `TNSubscriptionIOS/TNLog.swift`);
/// nothing vendor-specific lives here.
/// (Mọi engine dùng chung logger này, kể cả engine RevenueCat. Engine có SDK nhà cung cấp tự chuyển
/// mức log sang SDK đó — xem `TNAdaptyLog.swift`, `TNSubscriptionIOS/TNLog.swift`; ở đây không có gì
/// riêng của nhà cung cấp.)
package enum TNLog {

    private static let lock = NSLock()
    private static var _level: TNLogLevel = .default
    private static var _handler: ((TNLogLevel, String) -> Void)?
    private static var _output = Output.unifiedLog(makeLogger(category: "TNSubscription"))

    /// Where messages go when the app installed no handler. (Log đi đâu khi app không gắn handler.)
    private enum Output {
        /// `os.Logger`, under the engine's category in Console.app. (`os.Logger`, theo category của engine.)
        case unifiedLog(Logger)
        /// `print`, with a prefix — what the RevenueCat engine has always done.
        /// (`print` kèm tiền tố — cách engine RevenueCat vẫn làm từ trước.)
        case console(prefix: String)
    }

    private static func makeLogger(category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.tnsubscription", category: category)
    }

    /// Sends output to the unified log under `category`. Called by each engine's `configure`.
    /// (Gửi log vào unified log với `category`. Mỗi engine gọi trong `configure`.)
    package static func setCategory(_ category: String) {
        let logger = makeLogger(category: category)
        lock.lock()
        _output = .unifiedLog(logger)
        lock.unlock()
    }

    /// Sends output to `print` as `[prefix][LEVEL] message`. Used by the RevenueCat engine so its
    /// output stays exactly as it was.
    /// (Gửi log ra `print` dạng `[prefix][LEVEL] message`. Engine RevenueCat dùng để output giữ
    /// nguyên như cũ.)
    package static func setConsolePrefix(_ prefix: String) {
        lock.lock()
        _output = .console(prefix: prefix)
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
        let output = _output
        lock.unlock()

        guard threshold != .none, level >= threshold else { return }

        let text = message()
        if let sink {
            sink(level, text)
        } else {
            switch output {
            case .unifiedLog(let logger):
                logger.log(level: level.osLogType, "[\(level.description, privacy: .public)] \(text, privacy: .public)")
            case .console(let prefix):
                print("[\(prefix)][\(level)] \(text)")
            }
        }
    }

    package static func verbose(_ message: @autoclosure () -> String) { log(.verbose, message()) }
    package static func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    package static func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    package static func warn(_ message: @autoclosure () -> String) { log(.warn, message()) }
    package static func error(_ message: @autoclosure () -> String) { log(.error, message()) }
}

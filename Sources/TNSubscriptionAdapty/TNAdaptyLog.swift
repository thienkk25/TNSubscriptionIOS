import Foundation
import os
import Adapty

// MARK: - TNLogLevel ↔ Adapty

// `TNLogLevel` itself lives in TNSubscriptionShared; only the Adapty mapping is engine-specific.
// (`TNLogLevel` nằm trong TNSubscriptionShared; chỉ phần map sang Adapty là riêng của engine.)
extension TNLogLevel {

    /// The equivalent Adapty level. Adapty has no "off" level, so `.none` maps to `.error`
    /// and is then silenced by the forwarding handler instead.
    /// (Mức tương ứng của Adapty. Adapty không có mức "tắt", nên `.none` được map sang `.error`
    /// rồi bị handler chuyển tiếp chặn lại.)
    var adaptyLevel: AdaptyLog.Level {
        switch self {
        case .verbose: return .verbose
        case .debug: return .debug
        case .info: return .info
        case .warn: return .warn
        case .error, .none: return .error
        }
    }

    /// Maps an Adapty level onto a `TNLogLevel`, so SDK logs reach the host app's handler.
    /// (Map một mức của Adapty sang `TNLogLevel`, để log của SDK tới được handler của app.)
    init(adaptyLevel: AdaptyLog.Level) {
        switch adaptyLevel {
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

/// Internal logger. Routes messages to `TNSubscriptionAdapty.logHandler` when the host app
/// installed one, otherwise to the unified logging system (`os.Logger`).
/// (Logger nội bộ. Gửi log tới `TNSubscriptionAdapty.logHandler` nếu app có gắn, nếu không
/// thì gửi vào unified logging (`os.Logger`).)
///
/// Messages are passed as autoclosures, so string interpolation is never evaluated for a
/// message that the current threshold filters out.
/// (Thông điệp được truyền dạng autoclosure, nên chuỗi nội suy không bao giờ bị tính toán nếu
/// mức log hiện tại đã lọc bỏ nó.)
enum TNLog {

    private static let lock = NSLock()
    private static var _level: TNLogLevel = .default
    private static var _handler: ((TNLogLevel, String) -> Void)?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tnsubscription.adapty",
        category: "TNSubscriptionAdapty"
    )

    /// The current threshold. Setting it also retunes the Adapty SDK.
    /// (Ngưỡng hiện tại. Gán giá trị này cũng chỉnh luôn mức log của Adapty SDK.)
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
            Adapty.logLevel = newValue.adaptyLevel
        }
    }

    /// The host app's log sink, if installed.
    /// (Nơi nhận log của app, nếu đã gắn.)
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

    /// Routes Adapty's own log records through `log(_:_:)`, so one threshold and one handler
    /// govern everything.
    /// (Chuyển các bản ghi log của Adapty qua `log(_:_:)`, để một ngưỡng và một handler quản lý
    /// tất cả.)
    ///
    /// Without this, an app that sets `logLevel = .none` would still get Adapty's output, and a
    /// custom handler would see only half the story when debugging a failed purchase.
    /// (Nếu không có hàm này, app đặt `logLevel = .none` vẫn nhận log của Adapty, và handler riêng
    /// chỉ thấy một nửa câu chuyện khi debug một giao dịch thất bại.)
    static func bridgeAdaptyLogs() {
        Adapty.logLevel = level.adaptyLevel
        Adapty.setLogHandler { record in
            TNLog.log(TNLogLevel(adaptyLevel: record.level), "[Adapty] \(record.message)")
        }
    }

    /// Emits a message if `level` meets the current threshold.
    /// (Phát ra thông điệp nếu `level` đạt ngưỡng hiện tại.)
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
            logger.log(level: level.osLogType, "[\(level.description, privacy: .public)] \(text, privacy: .public)")
        }
    }

    static func verbose(_ message: @autoclosure () -> String) { log(.verbose, message()) }
    static func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    static func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    static func warn(_ message: @autoclosure () -> String) { log(.warn, message()) }
    static func error(_ message: @autoclosure () -> String) { log(.error, message()) }
}

import Foundation
import os
import Adapty

// MARK: - TNLogLevel

/// Severity levels for TNSubscriptionAdapty diagnostics, applied to both this package and the
/// underlying Adapty SDK.
/// (Các mức độ log cho TNSubscriptionAdapty, áp dụng cho cả package này lẫn Adapty SDK bên dưới.)
///
/// Levels are ordered: a message is emitted only when its level is **at or above** the
/// configured threshold. `.none` disables logging entirely.
/// (Các mức có thứ tự: một thông điệp chỉ được phát ra khi mức của nó **bằng hoặc cao hơn**
/// ngưỡng đã cấu hình. `.none` tắt log hoàn toàn.)
public enum TNLogLevel: Int, Comparable, CustomStringConvertible, Sendable {
    /// Every internal step, including Adapty's own verbose output.
    /// (Mọi bước nội bộ, kể cả log verbose của chính Adapty.)
    case verbose = 0
    /// Resolution details useful while debugging entitlement problems.
    /// (Chi tiết quá trình xác định quyền lợi, hữu ích khi debug.)
    case debug = 1
    /// Lifecycle milestones: configuration, unlocks, purchases, restores.
    /// (Các mốc vòng đời: cấu hình, mở khoá, mua, phục hồi.)
    case info = 2
    /// Misconfiguration and recoverable fallbacks.
    /// (Lỗi cấu hình và các trường hợp phải dùng phương án dự phòng.)
    case warn = 3
    /// Failures only.
    /// (Chỉ các lỗi thật sự.)
    case error = 4
    /// Logging disabled.
    /// (Tắt log.)
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

    /// The matching unified-logging level, used when no custom handler is installed.
    /// (Mức tương ứng trong unified logging, dùng khi chưa gắn handler riêng.)
    var osLogType: OSLogType {
        switch self {
        case .verbose, .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        case .none: return .debug
        }
    }

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

    /// Maps an Adapty level onto a `TNLogLevel`, so SDK logs can be forwarded to the host
    /// app's log handler.
    /// (Map một mức của Adapty sang `TNLogLevel`, để log của SDK được chuyển tới handler của app.)
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

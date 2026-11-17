import Foundation
import os

// MARK: - TNLogLevel

/// Severity levels for TNSubscriptionCore diagnostics.
/// (Các mức độ log cho TNSubscriptionCore.)
///
/// Levels are ordered: a message is emitted only when its level is **at or above**
/// the configured threshold. `.none` disables logging entirely.
///
/// ```swift
/// TNSubscriptionCore.logLevel = .verbose   // see every StoreKit transaction inspected
/// TNSubscriptionCore.logLevel = .none      // silence
/// ```
public enum TNLogLevel: Int, Comparable, CustomStringConvertible, Sendable {
    /// Every internal step, including each StoreKit transaction inspected.
    /// (Mọi bước nội bộ, kể cả từng giao dịch StoreKit được kiểm tra.)
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
}

// MARK: - TNLog

/// Internal logger. Routes messages to `TNSubscriptionCore.logHandler` when the host app
/// installed one, otherwise to the unified logging system (`os.Logger`).
/// (Logger nội bộ. Gửi log tới `TNSubscriptionCore.logHandler` nếu app có gắn, nếu không
/// thì gửi vào unified logging (`os.Logger`).)
///
/// Messages are passed as autoclosures, so string interpolation is never evaluated
/// for a message that the current threshold filters out.
/// (Thông điệp được truyền dạng autoclosure, nên chuỗi nội suy không bao giờ bị tính toán
/// nếu mức log hiện tại đã lọc bỏ nó.)
///
/// Unlike the RevenueCat-backed target there is no vendor SDK to forward levels to,
/// so `logLevel` only ever governs this package's own output.
/// (Khác với target dùng RevenueCat, ở đây không có SDK bên thứ ba nào để chuyển tiếp mức log,
/// nên `logLevel` chỉ điều khiển output của chính package này.)
enum TNLog {

    private static let lock = NSLock()
    private static var _level: TNLogLevel = .default
    private static var _handler: ((TNLogLevel, String) -> Void)?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tnsubscription.core",
        category: "TNSubscriptionCore"
    )

    /// The current threshold. Messages below it are dropped.
    /// (Ngưỡng hiện tại. Thông điệp dưới ngưỡng này bị bỏ.)
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
            // `privacy: .public` is required: without it the unified log redacts
            // interpolated values as <private>, which makes the diagnostics useless.
            logger.log(level: level.osLogType, "[\(level.description, privacy: .public)] \(text, privacy: .public)")
        }
    }

    static func verbose(_ message: @autoclosure () -> String) { log(.verbose, message()) }
    static func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    static func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    static func warn(_ message: @autoclosure () -> String) { log(.warn, message()) }
    static func error(_ message: @autoclosure () -> String) { log(.error, message()) }
}

import Foundation
import os

// MARK: - TNLogLevel

/// Severity levels for diagnostics — the same type in every engine.
/// (Các mức độ log — cùng một kiểu ở mọi engine.)
///
/// Levels are ordered: a message is emitted only when its level is **at or above** the
/// configured threshold. `.none` disables logging entirely. Each engine also applies this
/// threshold to its vendor SDK (RevenueCat, Adapty) where there is one.
/// (Các mức có thứ tự: một thông điệp chỉ được phát ra khi mức của nó **bằng hoặc cao hơn**
/// ngưỡng đã cấu hình. `.none` tắt log hoàn toàn. Mỗi engine cũng áp dụng ngưỡng này cho SDK của
/// nhà cung cấp (RevenueCat, Adapty) nếu có.)
public enum TNLogLevel: Int, Comparable, CustomStringConvertible, Sendable {
    /// Every internal step. (Mọi bước nội bộ.)
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
    /// Failures only. (Chỉ các lỗi thật sự.)
    case error = 4
    /// Logging disabled. (Tắt log.)
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

    /// The matching unified-logging level, for engines that log to `os.Logger`.
    /// (Mức tương ứng trong unified logging, cho các engine ghi log vào `os.Logger`.)
    package var osLogType: OSLogType {
        switch self {
        case .verbose, .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        case .none: return .debug
        }
    }
}

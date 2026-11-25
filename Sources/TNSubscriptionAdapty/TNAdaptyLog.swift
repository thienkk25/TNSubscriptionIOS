import Foundation
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

// MARK: - Adapty Log Bridge

// `TNLog` itself lives in TNSubscriptionShared; only the bridge to Adapty's logger is engine-specific.
// (`TNLog` nằm trong TNSubscriptionShared; chỉ phần nối sang logger của Adapty là riêng của engine.)
extension TNLog {

    /// Routes Adapty's own log records through `TNLog`, so one threshold and one handler govern
    /// everything.
    /// (Chuyển các bản ghi log của Adapty qua `TNLog`, để một ngưỡng và một handler quản lý tất cả.)
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
}

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

// `TNLog` itself lives in TNSubscriptionShared, shared with every engine; this engine only points
// its output at `print` (see `TNSubscriptionIOS.logLevel`), as it always has.
// (`TNLog` nằm trong TNSubscriptionShared, dùng chung với mọi engine; engine này chỉ đặt output ra
// `print` — xem `TNSubscriptionIOS.logLevel` — như từ trước tới nay.)

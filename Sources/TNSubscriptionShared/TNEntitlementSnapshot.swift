import Foundation

// MARK: - TNEntitlementSnapshot

/// A lock-protected mirror of the entitlement state, readable off the main actor.
/// (Bản sao trạng thái quyền lợi được bảo vệ bằng lock, đọc được ngoài main actor.)
///
/// The engines are `@MainActor`; this is what their `nonisolated` accessors read.
/// (Các engine là `@MainActor`; các accessor `nonisolated` của chúng đọc từ đây.)
package final class TNEntitlementSnapshot: @unchecked Sendable {
    package static let shared = TNEntitlementSnapshot()

    private let lock = NSLock()
    private var _isPremium = false
    private var _activeEntitlements: Set<String> = []

    private init() {}

    package var isPremium: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isPremium
    }

    package var activeEntitlements: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return _activeEntitlements
    }

    package func update(isPremium: Bool, active: Set<String>) {
        lock.lock()
        _isPremium = isPremium
        _activeEntitlements = active
        lock.unlock()
    }
}

// MARK: - TNEntitlementCache

/// The warm-start cache: which entitlements were active at the last check, and until when.
/// (Cache khởi động nóng: những quyền lợi nào đang hoạt động ở lần kiểm tra trước, và tới khi nào.)
///
/// Read synchronously at `configure`, before any `await`, so a subscriber never sees the paywall
/// flash while the real check is in flight. Each engine passes its own key, so switching engine
/// never trusts another engine's cache.
/// (Được đọc đồng bộ lúc `configure`, trước mọi `await`, để người đã đăng ký không thấy paywall
/// chớp lên trong lúc kiểm tra thật đang chạy. Mỗi engine dùng key riêng, nên đổi engine không bao
/// giờ tin cache của engine khác.)
package enum TNEntitlementCache {

    /// The cached entitlements that have not expired yet. (Các quyền lợi trong cache chưa hết hạn.)
    package static func unexpired(key: String, now: Date = Date()) -> Set<String> {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) else { return [] }
        var stillValid: Set<String> = []
        for (id, value) in raw {
            guard let timestamp = value as? Double else { continue }
            if Date(timeIntervalSince1970: timestamp) > now { stillValid.insert(id) }
        }
        return stillValid
    }

    /// Stores the active entitlements and their expiry; `nil` means it never expires.
    /// (Lưu các quyền lợi đang hoạt động và hạn của chúng; `nil` nghĩa là không bao giờ hết hạn.)
    ///
    /// Every value is a `Double`: `NSNull` is not a property-list type, and writing one makes
    /// `UserDefaults` throw (the bug fixed in 1.2.0).
    /// (Mọi giá trị đều là `Double`: `NSNull` không phải kiểu property list, và ghi nó khiến
    /// `UserDefaults` ném lỗi — lỗi đã sửa ở 1.2.0.)
    package static func store(_ expiries: [String: Date?], key: String) {
        guard !expiries.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        var payload: [String: Double] = [:]
        for (id, expiry) in expiries {
            payload[id] = (expiry ?? .distantFuture).timeIntervalSince1970
        }
        UserDefaults.standard.set(payload, forKey: key)
    }

    package static func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

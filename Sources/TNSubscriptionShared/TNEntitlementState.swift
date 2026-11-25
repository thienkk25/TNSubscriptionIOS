import Foundation

// MARK: - TNEntitlementState

/// Whether the user's access has been verified yet, and what it is.
/// (Quyền truy cập của người dùng đã được xác minh chưa, và kết quả là gì.)
///
/// Each engine exposes this as its nested `EntitlementState`, so `TNSubscription.EntitlementState`
/// reads the same whichever engine is imported.
/// (Mỗi engine expose kiểu này dưới tên lồng `EntitlementState`, nên
/// `TNSubscription.EntitlementState` đọc giống nhau dù import engine nào.)
public enum TNEntitlementState: String, Sendable {
    /// Not verified yet — show a loading state, never the paywall.
    /// (Chưa xác minh — hiển thị trạng thái đang tải, không bao giờ hiển thị paywall.)
    case unknown
    /// Verified: no access. (Đã xác minh: không có quyền.)
    case locked
    /// Verified, or restored from the warm-start cache: access granted.
    /// (Đã xác minh, hoặc khôi phục từ cache khởi động nóng: có quyền.)
    case unlocked
}

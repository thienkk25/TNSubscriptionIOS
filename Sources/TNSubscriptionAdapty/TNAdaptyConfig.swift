import Foundation

// `TNEntitlement` and `TNSubscriptionConfig` live in TNSubscriptionShared.
// (`TNEntitlement` và `TNSubscriptionConfig` nằm trong TNSubscriptionShared.)

// MARK: - API Key Validation

/// What is wrong with an API key, if anything.
/// (API key đang sai ở đâu, nếu có.)
enum TNAdaptyKeyProblem: Equatable {
    case empty
    /// A secret key, which must never ship in an app binary.
    /// (Secret key — tuyệt đối không được nằm trong binary của app.)
    case secretKey
    /// A RevenueCat key pasted by mistake — the commonest error when switching vendors.
    /// (Key RevenueCat bị dán nhầm — lỗi phổ biến nhất khi đổi nhà cung cấp.)
    case revenueCatKey
    case unrecognisedPrefix
    /// Right prefix, but shorter than any real key — usually a truncated paste.
    /// (Đúng tiền tố nhưng ngắn hơn mọi key thật — thường là dán bị cụt.)
    case tooShort

    /// The shortest key Adapty accepts. Taken from Adapty's own builder, which asserts
    /// `apiKey.count >= 41 && apiKey.starts(with: "public_live")`.
    /// (Độ dài key ngắn nhất mà Adapty chấp nhận. Lấy từ chính builder của Adapty.)
    static let minimumLength = 41

    /// Classifies a key without touching the network.
    /// (Phân loại key mà không cần mạng.)
    ///
    /// This runs **before** the key reaches Adapty, and a failing key is never passed on.
    /// Adapty validates with an `assert`, so a typo would otherwise crash every Debug build at
    /// launch rather than produce a readable error.
    /// (Hàm này chạy **trước khi** key tới Adapty, và key không hợp lệ sẽ không bao giờ được chuyển
    /// tiếp. Adapty kiểm tra bằng `assert`, nên nếu không chặn ở đây, một lỗi gõ phím sẽ làm crash
    /// mọi bản build Debug ngay khi khởi động thay vì báo lỗi dễ đọc.)
    static func check(_ apiKey: String) -> TNAdaptyKeyProblem? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return .empty }
        if key.hasPrefix("secret_") { return .secretKey }
        if key.hasPrefix("appl_") || key.hasPrefix("test_") || key.hasPrefix("goog_") { return .revenueCatKey }
        guard key.hasPrefix("public_live") else { return .unrecognisedPrefix }
        guard key.count >= minimumLength else { return .tooShort }
        return nil
    }

    /// A message that says what to do, not just what is wrong.
    /// (Thông điệp nói cần làm gì, không chỉ nói sai ở đâu.)
    var explanation: String {
        switch self {
        case .empty:
            return "The Adapty API key is empty. Pass your public SDK key (public_live_…) from Adapty → App settings → API keys."
        case .secretKey:
            return "This is an Adapty SECRET key. It must never ship inside an app — anyone can extract it from the binary. Use the public SDK key (public_live_…) and rotate this secret key now."
        case .revenueCatKey:
            return "This looks like a RevenueCat key (appl_/test_/goog_), not an Adapty one — the usual slip when switching vendors. Use your Adapty public SDK key (public_live_…)."
        case .unrecognisedPrefix:
            return "Unrecognised Adapty API key. Adapty public SDK keys start with 'public_live'."
        case .tooShort:
            return "The Adapty API key is shorter than \(Self.minimumLength) characters; it was probably truncated when copied."
        }
    }
}

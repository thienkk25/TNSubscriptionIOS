import Foundation

// MARK: - TNKeyProblem

/// What is wrong with an API key, if anything. (API key đang sai ở đâu, nếu có.)
package enum TNKeyProblem: Equatable, Sendable {
    /// No key at all. (Không có key.)
    case empty
    /// The key belongs to a different vendor — the usual slip when switching engines.
    /// (Key thuộc về nhà cung cấp khác — lỗi phổ biến nhất khi đổi engine.)
    case otherVendor(TNEngineKind)
    /// An Adapty **secret** key, which must never ship in an app.
    /// (**Secret** key của Adapty — tuyệt đối không được nằm trong app.)
    case secretKey
    /// The vendor is right but the format is not what this engine expects.
    /// (Đúng nhà cung cấp nhưng sai định dạng mà engine này cần.)
    case unexpectedFormat
    /// The right prefix, but shorter than any real key — usually a truncated paste.
    /// (Đúng tiền tố nhưng ngắn hơn mọi key thật — thường là dán bị cụt.)
    case tooShort(minimum: Int)
}

// MARK: - TNVendorKey

/// The single place that knows what each vendor's API key looks like.
/// (Nơi duy nhất biết key của từng nhà cung cấp trông như thế nào.)
///
/// Every engine checks its key through `check(_:for:)`. Before this existed each engine kept its own
/// list of other vendors' prefixes, and they disagreed: the Adapty engine recognised RevenueCat keys,
/// the Qonversion engine recognised RevenueCat and Adapty keys, and the RevenueCat engine recognised
/// neither — it passed an Adapty key straight to RevenueCat. Adding a vendor here now teaches every
/// engine at once.
/// (Mọi engine kiểm tra key qua `check(_:for:)`. Trước đây mỗi engine tự giữ danh sách tiền tố của
/// nhà cung cấp khác, và chúng không khớp nhau: engine Adapty nhận ra key RevenueCat, engine Qonversion
/// nhận ra key RevenueCat và Adapty, còn engine RevenueCat không nhận ra key nào — nó truyền thẳng key
/// Adapty cho RevenueCat. Giờ thêm một nhà cung cấp vào đây là mọi engine cùng biết.)
package enum TNVendorKey {

    /// Every recognisable key prefix and the vendor it belongs to. Qonversion is absent on purpose:
    /// its project keys have no prefix, so they cannot be recognised — only told apart from these.
    /// (Mọi tiền tố key nhận ra được và nhà cung cấp tương ứng. Qonversion cố ý không có mặt: project
    /// key của họ không có tiền tố nên không thể nhận diện — chỉ có thể phân biệt với các tiền tố này.)
    package static let knownPrefixes: [(prefix: String, vendor: TNEngineKind)] = [
        ("appl_", .revenueCat),         // App Store
        ("test_", .revenueCat),         // RevenueCat Test Store
        ("goog_", .revenueCat),         // Google Play
        ("amzn_", .revenueCat),         // Amazon Appstore
        ("public_live", .adapty),       // Adapty public SDK key
        ("secret_live", .adapty),       // Adapty secret key
    ]

    /// The shortest key Adapty accepts — from Adapty's own builder, which asserts
    /// `apiKey.count >= 41 && apiKey.starts(with: "public_live")`.
    /// (Độ dài key ngắn nhất mà Adapty chấp nhận — lấy từ chính builder của Adapty.)
    package static let adaptyMinimumLength = 41

    /// Which vendor a key appears to belong to, from its prefix; `nil` when it matches none.
    /// (Key có vẻ thuộc nhà cung cấp nào, dựa vào tiền tố; `nil` nếu không khớp tiền tố nào.)
    package static func vendor(ofKey key: String) -> TNEngineKind? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return knownPrefixes.first { trimmed.hasPrefix($0.prefix) }?.vendor
    }

    /// Checks a key for `engine`, without touching the network.
    /// (Kiểm tra key cho `engine`, không cần mạng.)
    package static func check(_ key: String, for engine: TNEngineKind) -> TNKeyProblem? {
        // Core talks only to Apple; any key is ignored (and `ignoredSettings` says so).
        if engine == .storeKit { return nil }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }

        if let vendor = vendor(ofKey: trimmed), vendor != engine {
            return .otherVendor(vendor)
        }

        switch engine {
        case .revenueCat:
            // App Store and Test Store keys are right for an iOS app. Anything else — a Google Play
            // or Amazon key, or a legacy key with no prefix — is flagged but not necessarily wrong.
            return (trimmed.hasPrefix("appl_") || trimmed.hasPrefix("test_")) ? nil : .unexpectedFormat
        case .adapty:
            if trimmed.hasPrefix("secret_live") { return .secretKey }
            guard trimmed.hasPrefix("public_live") else { return .unexpectedFormat }
            guard trimmed.count >= adaptyMinimumLength else { return .tooShort(minimum: adaptyMinimumLength) }
            return nil
        case .qonversion:
            // No prefix to check: a key that is not another vendor's is accepted.
            return nil
        case .storeKit:
            return nil
        }
    }
}

// MARK: - Policy And Messages

extension TNKeyProblem {

    /// Whether `engine` must refuse to start its SDK with this key.
    /// (Engine có phải từ chối khởi chạy SDK với key này hay không.)
    ///
    /// Everything blocks, with one exception: RevenueCat with an unexpected format. RevenueCat's
    /// legacy keys have no prefix and still work, so refusing them could take a live app's purchases
    /// down; that case is logged and the key is used.
    /// (Mọi trường hợp đều chặn, trừ một: RevenueCat với định dạng lạ. Key RevenueCat đời cũ không có
    /// tiền tố mà vẫn hoạt động, nên từ chối chúng có thể làm hỏng chức năng mua của app đang chạy thật;
    /// trường hợp đó chỉ ghi log và vẫn dùng key.)
    package func blocksLaunch(for engine: TNEngineKind) -> Bool {
        if engine == .revenueCat, self == .unexpectedFormat { return false }
        return true
    }

    /// A message that says what to do, not just what is wrong.
    /// (Thông điệp nói cần làm gì, không chỉ nói sai ở đâu.)
    package func explanation(for engine: TNEngineKind) -> String {
        let vendor = engine.vendorName
        switch self {
        case .empty:
            return "The \(vendor) API key is empty. \(engine.whereToFindKey)"
        case .otherVendor(let other):
            return "This looks like a \(other.vendorName) key, not a \(vendor) one — the usual slip when switching vendors. \(engine.whereToFindKey)"
        case .secretKey:
            return "This is an Adapty SECRET key. It must never ship inside an app — anyone can extract it from the binary. Use the public SDK key (public_live_…) and rotate this secret key now."
        case .unexpectedFormat:
            switch engine {
            case .revenueCat:
                return "Unexpected RevenueCat key prefix. An iOS app needs the App Store key (appl_…), or the Test Store key (test_…) during development. A goog_ or amzn_ key belongs to an Android or Amazon build. A key with no prefix may be a legacy RevenueCat key, which still works."
            case .adapty:
                return "Unrecognised Adapty API key. Adapty public SDK keys start with 'public_live'."
            case .qonversion, .storeKit:
                return "Unrecognised \(vendor) API key."
            }
        case .tooShort(let minimum):
            return "The \(vendor) API key is shorter than \(minimum) characters; it was probably truncated when copied."
        }
    }
}

extension TNEngineKind {

    /// The vendor's own name, for messages. (Tên nhà cung cấp, dùng trong thông điệp.)
    package var vendorName: String {
        switch self {
        case .revenueCat: return "RevenueCat"
        case .adapty: return "Adapty"
        case .qonversion: return "Qonversion"
        case .storeKit: return "StoreKit"
        }
    }

    /// Where in the vendor's dashboard the right key lives. (Key đúng nằm ở đâu trên dashboard.)
    package var whereToFindKey: String {
        switch self {
        case .revenueCat: return "Use the App Store public SDK key (appl_…) from RevenueCat → Project settings → API keys."
        case .adapty: return "Use the public SDK key (public_live_…) from Adapty → App settings → API keys."
        case .qonversion: return "Use the project key from Qonversion → Project settings."
        case .storeKit: return "TNSubscriptionCore needs no key."
        }
    }
}

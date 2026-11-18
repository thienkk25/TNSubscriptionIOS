import Foundation

// MARK: - TNEntitlement

/// One entitlement: an Adapty **access level**, plus the StoreKit product IDs that grant it.
/// (Một quyền lợi: một **access level** của Adapty, kèm các product ID StoreKit cấp quyền đó.)
///
/// ```swift
/// TNEntitlement(id: "premium", productIDs: ["com.app.weekly", "com.app.yearly"])
/// ```
///
/// - `id` must match the access level ID in the Adapty dashboard **exactly**, including case.
///   Adapty's default is `"premium"`, lowercase.
///   (`id` phải khớp **chính xác** với access level ID trên dashboard Adapty, kể cả chữ hoa/thường.
///   Mặc định của Adapty là `"premium"`, viết thường.)
/// - `productIDs` are not needed for the online path — Adapty already knows which product
///   grants which access level. They power the **offline fallback**: when Adapty cannot be
///   reached, the engine reads Apple's local `Transaction.currentEntitlements` and needs them to
///   know what a transaction unlocks.
///   (`productIDs` không cần cho luồng online — Adapty đã biết sản phẩm nào cấp access level nào.
///   Chúng phục vụ **phương án offline**: khi không kết nối được Adapty, engine đọc
///   `Transaction.currentEntitlements` cục bộ của Apple và cần chúng để biết một giao dịch mở khoá gì.)
public struct TNEntitlement: Hashable, Sendable {
    /// The Adapty access level ID (e.g. `"premium"`).
    /// (ID access level của Adapty, ví dụ `"premium"`.)
    public let id: String

    /// StoreKit product IDs that grant this access level, used by the offline fallback.
    /// (Các product ID StoreKit cấp access level này, dùng cho phương án offline.)
    public let productIDs: Set<String>

    public init(id: String, productIDs: Set<String> = []) {
        self.id = id
        self.productIDs = productIDs
    }
}

// MARK: - TNSubscriptionConfig

/// Configuration for the TNSubscriptionAdapty engine.
/// (Cấu hình cho engine TNSubscriptionAdapty.)
///
/// ```swift
/// TNSubscriptionAdapty.configure(config: TNSubscriptionConfig(
///     apiKey: "public_live_xxxxx",
///     entitlements: [
///         TNEntitlement(id: "premium", productIDs: ["com.app.weekly", "com.app.yearly"]),
///     ],
///     defaultPlacementId: "main"
/// ))
/// ```
///
/// Compared with `TNSubscriptionCore` there is an `apiKey` again, and **offerings are not
/// declared here**: they are Adapty placements, configured and A/B-tested in the dashboard.
/// (So với `TNSubscriptionCore`, ở đây lại có `apiKey`, và **offering không được khai báo ở đây**:
/// chúng là placement của Adapty, được cấu hình và A/B test trên dashboard.)
public struct TNSubscriptionConfig: Sendable {

    /// Your Adapty **public SDK key** (`public_live_…`). Never the secret key.
    /// (**Public SDK key** của Adapty (`public_live_…`). Tuyệt đối không dùng secret key.)
    public let apiKey: String

    /// The access levels this app sells.
    /// (Các access level app này bán.)
    public let entitlements: [TNEntitlement]

    /// The placement shown when a paywall does not name one. `nil` means every paywall must
    /// pass a placement ID explicitly.
    /// (Placement hiển thị khi paywall không chỉ định. `nil` nghĩa là mọi paywall đều phải truyền
    /// placement ID tường minh.)
    public let defaultPlacementId: String?

    /// Your own user ID, to tie the Adapty profile to an account. `nil` keeps the user anonymous;
    /// you can still call `identify(_:)` after login.
    /// (User ID của bạn, để gắn Adapty profile với một tài khoản. `nil` giữ người dùng ẩn danh;
    /// vẫn có thể gọi `identify(_:)` sau khi đăng nhập.)
    public let customerUserId: String?

    /// Observer mode: Adapty only *observes* purchases made by your own StoreKit code and does
    /// not make them. Leave `false` unless you are migrating gradually.
    /// (Chế độ quan sát: Adapty chỉ *quan sát* giao dịch do code StoreKit của bạn thực hiện, không
    /// tự thực hiện. Để `false` trừ khi bạn đang migrate từ từ.)
    public let observerMode: Bool

    /// Set to `false` to unlock everything without any purchase, and skip Adapty entirely.
    /// (Đặt `false` để mở khoá mọi thứ mà không cần mua, và bỏ qua Adapty hoàn toàn.)
    public let isIAPEnabled: Bool

    /// When `true`, `clientId` is sent to Adapty as the StoreKit `appAccountToken`, so App Store
    /// Server Notifications can be attributed to the same user. Requires a UUID `clientId`
    /// (the default).
    /// (Nếu `true`, `clientId` được gửi lên Adapty làm `appAccountToken` của StoreKit, để App Store
    /// Server Notifications quy được về cùng một user. Cần `clientId` là UUID — mặc định là vậy.)
    public let attachAppAccountToken: Bool

    /// When Adapty cannot be reached, fall back to Apple's local entitlements so a paying user
    /// is not locked out offline. Defaults to `true`.
    /// (Khi không kết nối được Adapty, dùng quyền lợi cục bộ của Apple để người đã trả tiền không
    /// bị khoá khi offline. Mặc định `true`.)
    ///
    /// Turn it off only if access must be revocable server-side even while offline — the local
    /// fallback cannot see a grant revoked from the Adapty dashboard.
    /// (Chỉ tắt khi quyền truy cập phải thu hồi được từ server ngay cả lúc offline — phương án cục
    /// bộ không thấy được một quyền bị thu hồi từ dashboard Adapty.)
    public let offlineStoreKitFallback: Bool

    /// Diagnostic verbosity, for this package and the Adapty SDK alike.
    /// (Mức độ log, áp dụng cho cả package này và Adapty SDK.)
    public let logLevel: TNLogLevel

    /// Every product ID across all configured entitlements.
    /// (Mọi product ID trong tất cả quyền lợi đã cấu hình.)
    public var allProductIDs: Set<String> {
        entitlements.reduce(into: Set<String>()) { $0.formUnion($1.productIDs) }
    }

    /// Every configured entitlement (access level) ID.
    /// (Mọi ID quyền lợi (access level) đã cấu hình.)
    public var allEntitlementIDs: [String] {
        entitlements.map(\.id)
    }

    public init(
        apiKey: String,
        entitlements: [TNEntitlement],
        defaultPlacementId: String? = nil,
        customerUserId: String? = nil,
        observerMode: Bool = false,
        isIAPEnabled: Bool = true,
        attachAppAccountToken: Bool = false,
        offlineStoreKitFallback: Bool = true,
        logLevel: TNLogLevel = .default
    ) {
        self.apiKey = apiKey
        self.entitlements = entitlements
        self.defaultPlacementId = defaultPlacementId
        self.customerUserId = customerUserId
        self.observerMode = observerMode
        self.isIAPEnabled = isIAPEnabled
        self.attachAppAccountToken = attachAppAccountToken
        self.offlineStoreKitFallback = offlineStoreKitFallback
        self.logLevel = logLevel
    }

    /// Convenience initialiser for the single-access-level case.
    /// (Khởi tạo tiện lợi cho trường hợp chỉ có một access level.)
    ///
    /// ```swift
    /// TNSubscriptionConfig(apiKey: "public_live_xxxxx", productIDs: ["com.app.weekly"], defaultPlacementId: "main")
    /// ```
    public init(
        apiKey: String,
        entitlementId: String = "premium",
        productIDs: Set<String> = [],
        defaultPlacementId: String? = nil,
        customerUserId: String? = nil,
        isIAPEnabled: Bool = true,
        logLevel: TNLogLevel = .default
    ) {
        self.init(
            apiKey: apiKey,
            entitlements: [TNEntitlement(id: entitlementId, productIDs: productIDs)],
            defaultPlacementId: defaultPlacementId,
            customerUserId: customerUserId,
            isIAPEnabled: isIAPEnabled,
            logLevel: logLevel
        )
    }
}

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

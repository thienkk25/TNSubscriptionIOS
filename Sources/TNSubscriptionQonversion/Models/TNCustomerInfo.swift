import Foundation
import StoreKit
import Qonversion

// MARK: - Supporting Enums

/// Where a purchase came from. Qonversion profiles are shared across platforms, so a subscription
/// bought on Android or the web unlocks here too.
/// (Giao dịch đến từ đâu. Profile Qonversion dùng chung giữa các nền tảng, nên subscription mua trên
/// Android hay web cũng mở khoá ở đây.)
public enum TNStore: String, Hashable, Sendable {
    /// The Apple App Store. (App Store của Apple.)
    case appStore
    /// Google Play. (Google Play.)
    case playStore
    /// A web checkout — Stripe or Paddle. (Thanh toán trên web — Stripe hoặc Paddle.)
    case web
    /// Granted by hand from the Qonversion dashboard. (Cấp thủ công từ dashboard Qonversion.)
    case promotional
    /// A source this version does not recognise. (Nguồn mà phiên bản này chưa biết.)
    case other

    /// Maps Qonversion's entitlement source. (Map nguồn entitlement của Qonversion.)
    static func from(qonversionSource source: Qonversion.EntitlementSource) -> TNStore {
        switch source {
        case .appStore: return .appStore
        case .playStore: return .playStore
        case .stripe, .paddle: return .web
        case .manual: return .promotional
        default: return .other
        }
    }
}

/// Which pricing phase a subscription is in. (Subscription đang ở giai đoạn giá nào.)
public enum TNPeriodType: String, Hashable, Sendable {
    /// Standard price. (Giá tiêu chuẩn.)
    case normal
    /// Free trial. (Dùng thử miễn phí.)
    case trial
    /// Paid introductory period. Qonversion does not distinguish it from `.normal`, so this engine
    /// never reports it. (Kỳ giới thiệu có phí. Qonversion không phân biệt với `.normal`, nên engine
    /// này không bao giờ trả về giá trị này.)
    case intro
    /// Granted through an offer code. (Được cấp qua offer code.)
    case promotional

    /// Classifies from Qonversion's entitlement fields. (Phân loại từ các trường entitlement của Qonversion.)
    ///
    /// An approximation: Qonversion reports when a trial started, not whether the current period is
    /// the trial. A trial that has not renewed yet is treated as still in trial.
    /// (Đây là ước lượng: Qonversion cho biết thời điểm bắt đầu dùng thử, chứ không cho biết kỳ hiện tại
    /// có phải kỳ dùng thử không. Một lần dùng thử chưa gia hạn lần nào được coi là vẫn đang dùng thử.)
    static func from(hasTrialStart: Bool, renewsCount: Int, grantType: Qonversion.EntitlementGrantType) -> TNPeriodType {
        if grantType == .offerCode { return .promotional }
        if hasTrialStart && renewsCount == 0 { return .trial }
        return .normal
    }
}

/// How the Apple ID came to own the product. (Apple ID sở hữu sản phẩm theo cách nào.)
public enum TNOwnershipType: String, Hashable, Sendable {
    case purchased
    case familyShared
    case unknown

    static func from(grantType: Qonversion.EntitlementGrantType) -> TNOwnershipType {
        switch grantType {
        case .purchase: return .purchased
        case .familySharing: return .familyShared
        default: return .unknown
        }
    }
}

/// Why a subscription is not in good standing, when it is not.
/// (Vì sao một subscription không ở trạng thái tốt, nếu đúng là vậy.)
public enum TNSubscriptionIssue: String, Hashable, Sendable {
    /// Billing failed and access has lapsed while the store retries.
    /// (Thanh toán thất bại và quyền truy cập đã mất trong lúc store thử lại.)
    case billingRetry
    /// Billing failed but access continues. (Thanh toán thất bại nhưng vẫn còn quyền truy cập.)
    case gracePeriod
    /// Refunded or revoked. Qonversion does not report this on the entitlement, so this engine
    /// never returns it. (Đã hoàn tiền hoặc bị thu hồi. Qonversion không báo trên entitlement, nên
    /// engine này không bao giờ trả về.)
    case revoked
    /// Expired normally. (Hết hạn bình thường.)
    case expired

    /// Classifies from Qonversion's renew state. (Phân loại từ trạng thái gia hạn của Qonversion.)
    static func classify(
        renewState: Qonversion.EntitlementRenewState,
        isActive: Bool,
        expirationDate: Date?,
        now: Date = Date()
    ) -> TNSubscriptionIssue? {
        if renewState == .billingIssue { return isActive ? .gracePeriod : .billingRetry }
        if !isActive, let expirationDate, expirationDate <= now { return .expired }
        return nil
    }
}

/// Whether auto-renew is on, from Qonversion's renew state.
/// (Tự gia hạn có đang bật không, theo trạng thái gia hạn của Qonversion.)
///
/// A billing issue still counts as "will renew": the user has not turned renewal off, the store is
/// retrying. An unknown state also counts as "will renew", because falsely telling a healthy
/// subscriber they are about to lapse is the worse error.
/// (Lỗi thanh toán vẫn tính là "sẽ gia hạn": người dùng chưa tắt gia hạn, store đang thử lại. Trạng
/// thái không rõ cũng tính là "sẽ gia hạn", vì báo sai rằng một subscription đang khoẻ sắp hết hạn là
/// lỗi tệ hơn.)
func tnWillRenew(_ renewState: Qonversion.EntitlementRenewState) -> Bool {
    switch renewState {
    case .willRenew, .billingIssue, .unknown: return true
    case .cancelled, .nonRenewable: return false
    default: return true
    }
}

/// Where an entitlement's state was read from. (Trạng thái quyền lợi được đọc từ đâu.)
public enum TNEntitlementSource: String, Hashable, Sendable {
    /// Qonversion's server — authoritative and cross-platform.
    /// (Server của Qonversion — chuẩn và đa nền tảng.)
    case qonversion
    /// Apple's local transactions, because Qonversion could not be reached.
    /// (Giao dịch cục bộ của Apple, vì không kết nối được Qonversion.)
    case storeKitFallback
}

// MARK: - TNEntitlementInfo

/// The state of one entitlement. (Trạng thái của một quyền lợi.)
public struct TNEntitlementInfo: Hashable, Sendable {
    /// The Qonversion entitlement ID. (ID entitlement của Qonversion.)
    public let identifier: String
    /// `true` while access is granted. (`true` khi đang được cấp quyền.)
    public let isActive: Bool
    /// The **App Store** product ID that granted it — mapped from Qonversion's own product ID.
    /// (Product ID **App Store** đã cấp quyền — được đổi từ product ID riêng của Qonversion.)
    public let productIdentifier: String
    /// `true` when the subscription will auto-renew. (`true` khi subscription sẽ tự gia hạn.)
    public let willRenew: Bool
    /// Which pricing phase it is in. (Đang ở giai đoạn giá nào.)
    public let periodType: TNPeriodType
    /// When it was last purchased or renewed. (Lần mua hoặc gia hạn gần nhất.)
    public let latestPurchaseDate: Date?
    /// When it was first purchased. (Lần mua đầu tiên.)
    public let originalPurchaseDate: Date?
    /// When access ends. `nil` for lifetime. (Khi nào hết quyền. `nil` nếu vĩnh viễn.)
    public let expirationDate: Date?
    /// When the user turned off auto-renew, if they did. (Khi người dùng tắt tự gia hạn, nếu có.)
    public let unsubscribeDetectedAt: Date?
    /// Where the purchase came from. (Giao dịch đến từ đâu.)
    public let store: TNStore
    /// `nil` on the Qonversion path, which does not report it. (`nil` ở luồng Qonversion, vì không được cung cấp.)
    public let isSandbox: Bool?
    /// How the Apple ID owns it. (Apple ID sở hữu theo cách nào.)
    public let ownershipType: TNOwnershipType
    /// The current problem, if any. (Vấn đề hiện tại, nếu có.)
    public let issue: TNSubscriptionIssue?
    /// Where this state came from. (Trạng thái này đến từ đâu.)
    public let source: TNEntitlementSource

    /// `true` during the grace period after a billing failure. (`true` trong thời gian ân hạn.)
    public var isInGracePeriod: Bool { issue == .gracePeriod }
    /// `true` while the store retries a failed charge and access has lapsed. (`true` khi đang thử lại thanh toán.)
    public var hasBillingIssue: Bool { issue == .billingRetry }

    /// Days until `expirationDate`, or `nil` for lifetime. (Số ngày còn lại, hoặc `nil` nếu vĩnh viễn.)
    public var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        let seconds = expirationDate.timeIntervalSinceNow
        return seconds > 0 ? Int(seconds / 86_400) : 0
    }

    /// Builds from a Qonversion entitlement. `storeProductID` is the App Store ID the engine mapped
    /// Qonversion's product ID to. (Dựng từ một entitlement của Qonversion. `storeProductID` là ID App
    /// Store mà engine đã đổi từ product ID của Qonversion.)
    init(entitlement: Qonversion.Entitlement, storeProductID: String) {
        identifier = entitlement.entitlementID
        isActive = entitlement.isActive
        productIdentifier = storeProductID
        willRenew = tnWillRenew(entitlement.renewState)
        periodType = .from(
            hasTrialStart: entitlement.trialStartDate != nil,
            renewsCount: Int(entitlement.renewsCount),
            grantType: entitlement.grantType
        )
        latestPurchaseDate = entitlement.lastPurchaseDate ?? entitlement.startedDate
        originalPurchaseDate = entitlement.firstPurchaseDate ?? entitlement.startedDate
        expirationDate = entitlement.expirationDate
        unsubscribeDetectedAt = entitlement.autoRenewDisableDate
        store = .from(qonversionSource: entitlement.source)
        isSandbox = nil
        ownershipType = .from(grantType: entitlement.grantType)
        issue = .classify(
            renewState: entitlement.renewState,
            isActive: entitlement.isActive,
            expirationDate: entitlement.expirationDate
        )
        source = .qonversion
    }

    /// Builds from a verified local StoreKit transaction, for the offline fallback.
    /// (Dựng từ một giao dịch StoreKit cục bộ đã xác minh, cho phương án offline.)
    init(entitlementId: String, transaction: StoreKit.Transaction) {
        identifier = entitlementId
        isActive = true
        productIdentifier = transaction.productID
        willRenew = transaction.productType == .autoRenewable
        periodType = .normal
        latestPurchaseDate = transaction.purchaseDate
        originalPurchaseDate = transaction.originalPurchaseDate
        expirationDate = transaction.expirationDate
        unsubscribeDetectedAt = nil
        store = .appStore
        isSandbox = transaction.environment != .production
        ownershipType = transaction.ownershipType == .familyShared ? .familyShared : .purchased
        issue = nil
        source = .storeKitFallback
    }
}

// MARK: - TNEntitlementInfos

/// A keyed collection of entitlement states. (Tập trạng thái quyền lợi theo key.)
public struct TNEntitlementInfos: Hashable, Sendable {
    public let all: [String: TNEntitlementInfo]

    public init(all: [String: TNEntitlementInfo] = [:]) {
        self.all = all
    }

    public var active: [String: TNEntitlementInfo] { all.filter { $0.value.isActive } }
    public var activeIdentifiers: Set<String> { Set(active.keys) }
    public subscript(identifier: String) -> TNEntitlementInfo? { all[identifier] }
}

// MARK: - TNCustomerInfo

/// A snapshot of everything this user is entitled to. (Snapshot mọi thứ người dùng này được hưởng.)
public struct TNCustomerInfo: Hashable, Sendable {
    public let entitlements: TNEntitlementInfos
    /// App Store IDs of active subscriptions. (ID App Store của các subscription đang hoạt động.)
    public let activeSubscriptions: Set<String>
    /// App Store IDs of everything owned. (ID App Store của mọi thứ đang sở hữu.)
    public let allPurchasedProductIdentifiers: Set<String>
    public let latestExpirationDate: Date?
    public let originalPurchaseDate: Date?
    public let requestDate: Date
    /// Where this snapshot came from. (Snapshot này đến từ đâu.)
    public let source: TNEntitlementSource
    public let managementURL: URL? = URL(string: "https://apps.apple.com/account/subscriptions")

    public var hasActiveEntitlement: Bool { !entitlements.active.isEmpty }

    public init(
        entitlements: TNEntitlementInfos = TNEntitlementInfos(),
        activeSubscriptions: Set<String> = [],
        allPurchasedProductIdentifiers: Set<String> = [],
        latestExpirationDate: Date? = nil,
        originalPurchaseDate: Date? = nil,
        requestDate: Date = Date(),
        source: TNEntitlementSource = .qonversion
    ) {
        self.entitlements = entitlements
        self.activeSubscriptions = activeSubscriptions
        self.allPurchasedProductIdentifiers = allPurchasedProductIdentifiers
        self.latestExpirationDate = latestExpirationDate
        self.originalPurchaseDate = originalPurchaseDate
        self.requestDate = requestDate
        self.source = source
    }
}

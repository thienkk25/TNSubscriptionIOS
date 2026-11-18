import Foundation
import StoreKit
import Adapty

// MARK: - Supporting Enums

/// Where a purchase came from.
/// (Giao dịch đến từ đâu.)
///
/// Unlike `TNSubscriptionCore`, this can name stores other than Apple's: an Adapty profile
/// is shared across platforms, so a subscription bought on Android or the web unlocks here too.
/// (Khác với `TNSubscriptionCore`, ở đây có thể có store khác ngoài Apple: Adapty profile dùng
/// chung giữa các nền tảng, nên subscription mua trên Android hay web cũng mở khoá ở đây.)
public enum TNStore: String, Hashable, Sendable {
    /// The Apple App Store. (App Store của Apple.)
    case appStore
    /// Google Play — a purchase from the Android build of the app. (Google Play — mua từ bản Android.)
    case playStore
    /// A web checkout such as Stripe or Paddle. (Thanh toán trên web như Stripe hay Paddle.)
    case web
    /// Granted by hand from the Adapty dashboard, e.g. for support or a promotion.
    /// (Cấp thủ công từ dashboard Adapty, ví dụ cho hỗ trợ khách hàng hoặc khuyến mãi.)
    case promotional
    /// A store this version does not recognise. (Một store mà phiên bản này chưa biết.)
    case other

    /// Maps Adapty's store string. (Map chuỗi store của Adapty.)
    static func from(adaptyStore store: String) -> TNStore {
        switch store.lowercased() {
        case "app_store": return .appStore
        case "play_store": return .playStore
        case "stripe", "paddle", "web": return .web
        case "adapty", "promotional": return .promotional
        default: return .other
        }
    }
}

/// Which pricing phase a subscription is currently in.
/// (Subscription đang ở giai đoạn giá nào.)
public enum TNPeriodType: String, Hashable, Sendable {
    /// Paying the standard price. (Đang trả giá tiêu chuẩn.)
    case normal
    /// In a free trial. (Đang dùng thử miễn phí.)
    case trial
    /// In a paid introductory period. (Đang trong kỳ giới thiệu có phí.)
    case intro
    /// Under a promotional or win-back offer. (Đang hưởng ưu đãi promotional hoặc win-back.)
    case promotional

    /// Classifies from Adapty's active-offer fields. (Phân loại từ các trường ưu đãi của Adapty.)
    static func from(introductoryOfferType intro: String?, promotionalOfferType promo: String?) -> TNPeriodType {
        if promo != nil { return .promotional }
        switch intro {
        case "free_trial": return .trial
        case .some: return .intro
        case .none: return .normal
        }
    }
}

/// How the Apple ID came to own the product. (Apple ID sở hữu sản phẩm theo cách nào.)
public enum TNOwnershipType: String, Hashable, Sendable {
    case purchased
    case familyShared
    /// Adapty's profile does not report ownership, so this is the value on the online path.
    /// (Profile của Adapty không báo hình thức sở hữu, nên đây là giá trị ở luồng online.)
    case unknown
}

/// Why a subscription is not in good standing, when it is not.
/// (Vì sao một subscription không ở trạng thái tốt, nếu đúng là vậy.)
public enum TNSubscriptionIssue: String, Hashable, Sendable {
    /// Billing failed and access has lapsed while the store retries.
    /// (Thanh toán thất bại và quyền truy cập đã mất trong lúc store thử lại.)
    case billingRetry
    /// Billing failed but access continues during the grace period.
    /// (Thanh toán thất bại nhưng quyền truy cập vẫn còn trong thời gian ân hạn.)
    case gracePeriod
    /// Refunded or revoked. (Đã hoàn tiền hoặc bị thu hồi.)
    case revoked
    /// Expired normally. (Hết hạn bình thường.)
    case expired

    /// Classifies from plain values, in order of severity.
    /// (Phân loại từ các giá trị thuần, theo thứ tự mức độ nghiêm trọng.)
    ///
    /// A refund wins over everything; a billing problem with continued access is a grace
    /// period, without it a retry.
    /// (Hoàn tiền được ưu tiên trên hết; lỗi thanh toán mà vẫn còn quyền là ân hạn, mất quyền là
    /// đang thử lại.)
    static func classify(
        isRefund: Bool,
        isActive: Bool,
        isInGracePeriod: Bool,
        billingIssueDetectedAt: Date?,
        expiresAt: Date?,
        now: Date = Date()
    ) -> TNSubscriptionIssue? {
        if isRefund { return .revoked }
        if isInGracePeriod { return .gracePeriod }
        if billingIssueDetectedAt != nil { return isActive ? .gracePeriod : .billingRetry }
        if !isActive, let expiresAt, expiresAt <= now { return .expired }
        return nil
    }
}

/// Where an entitlement's state was read from.
/// (Trạng thái quyền lợi được đọc từ đâu.)
public enum TNEntitlementSource: String, Hashable, Sendable {
    /// Adapty's server profile — the authoritative answer, cross-platform.
    /// (Profile trên server Adapty — câu trả lời chuẩn, đa nền tảng.)
    case adapty
    /// Apple's local transactions, because Adapty could not be reached. Correct for App Store
    /// purchases, but blind to cross-platform and dashboard grants.
    /// (Giao dịch cục bộ của Apple, vì không kết nối được Adapty. Đúng với giao dịch App Store,
    /// nhưng không thấy quyền từ nền tảng khác hay quyền cấp từ dashboard.)
    case storeKitFallback
}

// MARK: - TNEntitlementInfo

/// The state of one entitlement (Adapty access level).
/// (Trạng thái của một quyền lợi (access level của Adapty).)
public struct TNEntitlementInfo: Hashable, Sendable {

    /// The access level ID (e.g. `"premium"`). (ID access level, ví dụ `"premium"`.)
    public let identifier: String
    /// `true` while access is granted. (`true` khi đang được cấp quyền truy cập.)
    public let isActive: Bool
    /// The product that granted it. (Sản phẩm đã cấp quyền này.)
    public let productIdentifier: String
    /// `true` when the subscription will auto-renew. (`true` khi subscription sẽ tự gia hạn.)
    public let willRenew: Bool
    /// Which pricing phase the subscription is in. (Subscription đang ở giai đoạn giá nào.)
    public let periodType: TNPeriodType
    /// When it was last purchased or renewed. (Lần mua hoặc gia hạn gần nhất.)
    public let latestPurchaseDate: Date?
    /// When it was first activated. (Lần kích hoạt đầu tiên.)
    public let originalPurchaseDate: Date?
    /// When access ends. `nil` for lifetime. (Khi nào hết quyền. `nil` nếu vĩnh viễn.)
    public let expirationDate: Date?
    /// When the user turned off auto-renew, if they did. (Khi người dùng tắt tự gia hạn, nếu có.)
    public let unsubscribeDetectedAt: Date?
    /// When a billing problem was first seen, if any. (Khi phát hiện lỗi thanh toán, nếu có.)
    public let billingIssueDetectedAt: Date?
    /// Where the purchase came from. (Giao dịch đến từ đâu.)
    public let store: TNStore
    /// `true`/`false` when known; `nil` when the source does not say.
    /// (`true`/`false` khi biết được; `nil` khi nguồn dữ liệu không cho biết.)
    public let isSandbox: Bool?
    /// How the Apple ID owns it. (Apple ID sở hữu theo cách nào.)
    public let ownershipType: TNOwnershipType
    /// The current problem, if any. (Vấn đề hiện tại, nếu có.)
    public let issue: TNSubscriptionIssue?
    /// Where this state came from. (Trạng thái này đến từ đâu.)
    public let source: TNEntitlementSource

    /// `true` during the grace period after a billing failure.
    /// (`true` trong thời gian ân hạn sau khi thanh toán thất bại.)
    public var isInGracePeriod: Bool { issue == .gracePeriod }

    /// `true` while the store retries a failed charge and access has lapsed.
    /// (`true` khi store đang thử lại lần trừ tiền thất bại và quyền truy cập đã mất.)
    public var hasBillingIssue: Bool { issue == .billingRetry }

    /// Days until `expirationDate`, or `nil` for lifetime. (Số ngày còn lại, hoặc `nil` nếu vĩnh viễn.)
    public var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        let seconds = expirationDate.timeIntervalSinceNow
        return seconds > 0 ? Int(seconds / 86_400) : 0
    }

    /// Builds from an Adapty access level. (Dựng từ một access level của Adapty.)
    init(accessLevel level: AdaptyProfile.AccessLevel, isSandbox: Bool?) {
        identifier = level.id
        isActive = level.isActive
        productIdentifier = level.vendorProductId
        willRenew = level.willRenew
        periodType = .from(
            introductoryOfferType: level.activeIntroductoryOfferType,
            promotionalOfferType: level.activePromotionalOfferType
        )
        latestPurchaseDate = level.renewedAt ?? level.activatedAt
        originalPurchaseDate = level.activatedAt
        expirationDate = level.isLifetime ? nil : level.expiresAt
        unsubscribeDetectedAt = level.unsubscribedAt
        billingIssueDetectedAt = level.billingIssueDetectedAt
        store = .from(adaptyStore: level.store)
        self.isSandbox = isSandbox
        ownershipType = .unknown
        issue = .classify(
            isRefund: level.isRefund,
            isActive: level.isActive,
            isInGracePeriod: level.isInGracePeriod,
            billingIssueDetectedAt: level.billingIssueDetectedAt,
            expiresAt: level.expiresAt
        )
        source = .adapty
    }

    /// Builds from a verified local StoreKit transaction, for the offline fallback.
    /// (Dựng từ một giao dịch StoreKit cục bộ đã xác minh, cho phương án offline.)
    init(entitlementId: String, transaction: StoreKit.Transaction) {
        identifier = entitlementId
        isActive = true
        productIdentifier = transaction.productID
        // Renewal intent is unknown offline; assuming it renews avoids a false "expiring" banner.
        willRenew = transaction.productType == .autoRenewable
        periodType = .normal
        latestPurchaseDate = transaction.purchaseDate
        originalPurchaseDate = transaction.originalPurchaseDate
        expirationDate = transaction.expirationDate
        unsubscribeDetectedAt = nil
        billingIssueDetectedAt = nil
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
    /// Every entitlement known, active or not. (Mọi quyền lợi đã biết, hoạt động hay không.)
    public let all: [String: TNEntitlementInfo]

    public init(all: [String: TNEntitlementInfo] = [:]) {
        self.all = all
    }

    /// Only the active ones. (Chỉ các quyền lợi đang hoạt động.)
    public var active: [String: TNEntitlementInfo] { all.filter { $0.value.isActive } }

    /// IDs of the active ones. (ID của các quyền lợi đang hoạt động.)
    public var activeIdentifiers: Set<String> { Set(active.keys) }

    public subscript(identifier: String) -> TNEntitlementInfo? { all[identifier] }
}

// MARK: - TNCustomerInfo

/// A snapshot of everything this user is entitled to.
/// (Snapshot mọi thứ người dùng này được hưởng.)
public struct TNCustomerInfo: Hashable, Sendable {

    /// The configured access levels. (Các access level đã cấu hình.)
    public let entitlements: TNEntitlementInfos
    /// Product IDs of active subscriptions. (Product ID của các subscription đang hoạt động.)
    public let activeSubscriptions: Set<String>
    /// Product IDs of everything owned. (Product ID của mọi thứ đang sở hữu.)
    public let allPurchasedProductIdentifiers: Set<String>
    /// Product IDs of non-subscription purchases. (Product ID của các giao dịch không phải subscription.)
    public let nonSubscriptionProductIdentifiers: Set<String>
    /// The furthest-out expiry among active entitlements. (Ngày hết hạn xa nhất trong các quyền lợi đang hoạt động.)
    public let latestExpirationDate: Date?
    /// The earliest activation — "customer since". (Lần kích hoạt sớm nhất — "khách hàng từ khi nào".)
    public let originalPurchaseDate: Date?
    /// When this snapshot was taken. (Thời điểm tạo snapshot.)
    public let requestDate: Date
    /// Adapty's profile ID; `nil` on the offline fallback. (Profile ID của Adapty; `nil` khi offline.)
    public let profileId: String?
    /// Your own user ID, if `identify(_:)` was called. (User ID của bạn, nếu đã gọi `identify(_:)`.)
    public let customerUserId: String?
    /// Where this snapshot came from. (Snapshot này đến từ đâu.)
    public let source: TNEntitlementSource
    /// Apple's subscription management page. (Trang quản lý đăng ký của Apple.)
    public let managementURL: URL? = URL(string: "https://apps.apple.com/account/subscriptions")

    /// `true` when at least one entitlement is active. (`true` khi có ít nhất một quyền lợi đang hoạt động.)
    public var hasActiveEntitlement: Bool { !entitlements.active.isEmpty }

    public init(
        entitlements: TNEntitlementInfos = TNEntitlementInfos(),
        activeSubscriptions: Set<String> = [],
        allPurchasedProductIdentifiers: Set<String> = [],
        nonSubscriptionProductIdentifiers: Set<String> = [],
        latestExpirationDate: Date? = nil,
        originalPurchaseDate: Date? = nil,
        requestDate: Date = Date(),
        profileId: String? = nil,
        customerUserId: String? = nil,
        source: TNEntitlementSource = .adapty
    ) {
        self.entitlements = entitlements
        self.activeSubscriptions = activeSubscriptions
        self.allPurchasedProductIdentifiers = allPurchasedProductIdentifiers
        self.nonSubscriptionProductIdentifiers = nonSubscriptionProductIdentifiers
        self.latestExpirationDate = latestExpirationDate
        self.originalPurchaseDate = originalPurchaseDate
        self.requestDate = requestDate
        self.profileId = profileId
        self.customerUserId = customerUserId
        self.source = source
    }

    /// Builds a snapshot from an Adapty profile, keeping only the configured access levels.
    /// (Dựng snapshot từ một Adapty profile, chỉ giữ các access level đã cấu hình.)
    init(profile: AdaptyProfile, configuredIds: Set<String>) {
        var infos: [String: TNEntitlementInfo] = [:]
        for (id, level) in profile.accessLevels where configuredIds.contains(id) {
            let sandbox = profile.subscriptions[level.vendorProductId]?.isSandbox
            infos[id] = TNEntitlementInfo(accessLevel: level, isSandbox: sandbox)
        }

        let activeSubs = Set(profile.subscriptions.values.filter(\.isActive).map(\.vendorProductId))
        let nonSubs = Set(profile.nonSubscriptions.values.flatMap { $0 }.filter { !$0.isRefund }.map(\.vendorProductId))
        let active = infos.values.filter(\.isActive)

        self.init(
            entitlements: TNEntitlementInfos(all: infos),
            activeSubscriptions: activeSubs,
            allPurchasedProductIdentifiers: activeSubs.union(nonSubs),
            nonSubscriptionProductIdentifiers: nonSubs,
            latestExpirationDate: active.compactMap(\.expirationDate).max(),
            originalPurchaseDate: infos.values.compactMap(\.originalPurchaseDate).min(),
            profileId: profile.profileId,
            customerUserId: profile.customerUserId,
            source: .adapty
        )
    }
}

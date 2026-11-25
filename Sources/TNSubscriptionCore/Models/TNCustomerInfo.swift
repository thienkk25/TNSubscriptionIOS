import Foundation
import StoreKit

// MARK: - Supporting Enums

/// Where a purchase originated.
///
/// StoreKit 2 only ever reports Apple transactions, so there is no `.playStore` / `.stripe`
/// case here — that is the price of dropping a cross-platform backend.
/// (StoreKit 2 chỉ báo về giao dịch của Apple, nên ở đây không có `.playStore` / `.stripe` —
/// đó là cái giá của việc bỏ backend đa nền tảng.)
public enum TNStore: String, Hashable, Sendable {
    /// Bought on the App Store by this Apple ID.
    /// (Mua trên App Store bằng chính Apple ID này.)
    case appStore
    /// Shared with this Apple ID through Family Sharing.
    /// (Được chia sẻ tới Apple ID này qua Family Sharing.)
    case familyShared
    /// Granted by Xcode / a `.storekit` configuration file, or the sandbox environment.
    /// (Do Xcode / file cấu hình `.storekit` cấp, hoặc từ môi trường sandbox.)
    case sandbox
}

/// Which pricing phase a subscription is currently in.
/// (Subscription đang ở giai đoạn giá nào.)
public enum TNPeriodType: String, Hashable, Sendable {
    /// Paying the standard price.
    /// (Đang trả giá tiêu chuẩn.)
    case normal
    /// In a free trial.
    /// (Đang trong thời gian dùng thử miễn phí.)
    case trial
    /// In a paid introductory period.
    /// (Đang trong kỳ giới thiệu có phí.)
    case intro
    /// Redeemed a promotional offer (offer code or developer-signed offer).
    /// (Đã dùng một ưu đãi khuyến mãi — offer code hoặc ưu đãi do nhà phát triển ký.)
    case promotional
}

/// How the Apple ID came to own the product.
/// (Apple ID sở hữu sản phẩm này theo cách nào.)
public enum TNOwnershipType: String, Hashable, Sendable {
    /// Bought directly.
    /// (Tự mua trực tiếp.)
    case purchased
    /// Received through Family Sharing.
    /// (Nhận được qua Family Sharing.)
    case familyShared
    /// StoreKit reported something this version does not know about.
    /// (StoreKit báo về một giá trị mà phiên bản này chưa biết.)
    case unknown
}

/// Why a subscription is no longer in good standing, when it is not.
/// (Vì sao một subscription không còn ở trạng thái tốt, nếu đúng là như vậy.)
public enum TNSubscriptionIssue: String, Hashable, Sendable {
    /// Apple could not charge the card; the subscription is in billing retry.
    /// (Apple không trừ được tiền thẻ; subscription đang trong giai đoạn thử lại thanh toán.)
    case billingRetry
    /// Billing failed but Apple is still serving the entitlement during the grace period.
    /// (Thanh toán thất bại nhưng Apple vẫn cấp quyền lợi trong thời gian gia hạn ân hạn.)
    case gracePeriod
    /// Refunded or revoked by Apple.
    /// (Đã hoàn tiền hoặc bị Apple thu hồi.)
    case revoked
    /// Expired normally.
    /// (Hết hạn bình thường.)
    case expired
}

// MARK: - TNEntitlementInfo

/// The state of one entitlement, assembled from the verified StoreKit transaction that grants it.
///
/// This mirrors the shape of RevenueCat's `EntitlementInfo` so paywall and settings code
/// reads the same, but every field here comes from Apple's signed JWS payload on-device.
/// (Struct này mô phỏng hình dạng của `EntitlementInfo` trong RevenueCat để code paywall và
/// cài đặt đọc giống nhau, nhưng mọi thuộc tính ở đây đều đến từ payload JWS có chữ ký của
/// Apple, xác minh ngay trên thiết bị.)
public struct TNEntitlementInfo: Hashable, Sendable {

    /// The entitlement identifier from your `TNEntitlement` config (e.g. `"Premium"`).
    /// (ID quyền lợi lấy từ cấu hình `TNEntitlement` của bạn, ví dụ `"Premium"`.)
    public let identifier: String

    /// `true` when the granting transaction is verified, unrevoked and unexpired.
    /// (`true` khi giao dịch cấp quyền đã được xác minh, chưa bị thu hồi và chưa hết hạn.)
    public let isActive: Bool

    /// The product ID that granted this entitlement.
    /// (Product ID đã cấp quyền lợi này.)
    public let productIdentifier: String

    /// `true` when Apple reports the subscription will auto-renew at period end.
    /// Always `false` for non-renewing products (lifetime), and `true` when renewal
    /// state could not be read (products not yet loaded) to avoid false "expiring soon" UI.
    /// (`true` khi Apple báo subscription sẽ tự gia hạn ở cuối kỳ. Luôn `false` với sản phẩm
    /// không gia hạn (vĩnh viễn), và `true` khi chưa đọc được trạng thái gia hạn (sản phẩm chưa
    /// tải xong) để tránh hiện UI "sắp hết hạn" sai.)
    public let willRenew: Bool

    /// Which pricing phase the subscription is in.
    /// (Subscription đang ở giai đoạn giá nào.)
    public let periodType: TNPeriodType

    /// When the granting transaction was purchased (or last renewed).
    /// (Thời điểm giao dịch cấp quyền được mua — hoặc lần gia hạn gần nhất.)
    public let latestPurchaseDate: Date?

    /// When the subscription was first ever purchased, across all renewals.
    /// (Thời điểm subscription được mua lần đầu tiên, tính qua mọi lần gia hạn.)
    public let originalPurchaseDate: Date?

    /// When access ends. `nil` for lifetime (non-consumable) purchases.
    /// (Thời điểm hết quyền truy cập. `nil` với giao dịch vĩnh viễn (non-consumable).)
    public let expirationDate: Date?

    /// When Apple revoked the purchase (refund, family-sharing removal). `nil` normally.
    /// (Thời điểm Apple thu hồi giao dịch — hoàn tiền, rời Family Sharing. Thường là `nil`.)
    public let revocationDate: Date?

    /// Where the purchase came from.
    /// (Giao dịch đến từ đâu.)
    public let store: TNStore

    /// `true` when the transaction came from the sandbox or an Xcode `.storekit` file.
    /// (`true` khi giao dịch đến từ sandbox hoặc file `.storekit` của Xcode.)
    public let isSandbox: Bool

    /// How the Apple ID owns the product.
    /// (Apple ID sở hữu sản phẩm theo cách nào.)
    public let ownershipType: TNOwnershipType

    /// The current problem with this subscription, if any. `nil` when healthy.
    /// (Vấn đề hiện tại của subscription này, nếu có. `nil` khi mọi thứ bình thường.)
    public let issue: TNSubscriptionIssue?

    /// The underlying verified StoreKit transaction, in case you need a field this struct does not expose.
    /// (Giao dịch StoreKit đã xác minh bên dưới, dùng khi bạn cần một thuộc tính struct này chưa expose.)
    public let transaction: StoreKit.Transaction

    /// `true` when the subscription is in the paid grace period after a billing failure:
    /// still entitled, but at risk. A good trigger for a "please update your payment method" banner.
    /// (`true` khi subscription đang trong thời gian ân hạn sau khi thanh toán thất bại: vẫn còn
    /// quyền lợi, nhưng đang có nguy cơ mất. Thời điểm tốt để hiện banner "vui lòng cập nhật
    /// phương thức thanh toán".)
    public var isInGracePeriod: Bool { issue == .gracePeriod }

    /// `true` when Apple is retrying a failed charge and access has already lapsed.
    /// (`true` khi Apple đang thử lại một lần trừ tiền thất bại và quyền truy cập đã mất.)
    public var hasBillingIssue: Bool { issue == .billingRetry }

    /// Days remaining until `expirationDate`, or `nil` for lifetime purchases.
    /// (Số ngày còn lại tới `expirationDate`, hoặc `nil` với giao dịch vĩnh viễn.)
    public var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        let seconds = expirationDate.timeIntervalSinceNow
        guard seconds > 0 else { return 0 }
        return Int(seconds / 86_400)
    }

    public static func == (lhs: TNEntitlementInfo, rhs: TNEntitlementInfo) -> Bool {
        lhs.identifier == rhs.identifier
            && lhs.isActive == rhs.isActive
            && lhs.productIdentifier == rhs.productIdentifier
            && lhs.expirationDate == rhs.expirationDate
            && lhs.willRenew == rhs.willRenew
            && lhs.issue == rhs.issue
            && lhs.transaction.id == rhs.transaction.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(transaction.id)
        hasher.combine(isActive)
    }
}

// MARK: - TNEntitlementInfos

/// A keyed collection of entitlement states, with the same `all` / `active` / subscript
/// shape as RevenueCat's `EntitlementInfos`.
/// (Tập hợp trạng thái quyền lợi theo key, có cùng hình dạng `all` / `active` / subscript như
/// `EntitlementInfos` của RevenueCat.)
public struct TNEntitlementInfos: Hashable, Sendable {

    /// Every entitlement the engine knows about, active or not.
    /// (Mọi quyền lợi engine biết tới, đang hoạt động hay không.)
    public let all: [String: TNEntitlementInfo]

    public init(all: [String: TNEntitlementInfo] = [:]) {
        self.all = all
    }

    /// Only the entitlements that are currently active.
    /// (Chỉ các quyền lợi đang hoạt động.)
    public var active: [String: TNEntitlementInfo] {
        all.filter { $0.value.isActive }
    }

    /// The IDs of the currently active entitlements.
    /// (ID của các quyền lợi đang hoạt động.)
    public var activeIdentifiers: Set<String> {
        Set(active.keys)
    }

    public subscript(identifier: String) -> TNEntitlementInfo? {
        all[identifier]
    }
}

// MARK: - TNCustomerInfo

/// A snapshot of everything this Apple ID is entitled to, built entirely from
/// `Transaction.currentEntitlements`.
///
/// The local replacement for RevenueCat's `CustomerInfo`. Two deliberate differences:
/// (Bản thay thế cục bộ cho `CustomerInfo` của RevenueCat. Có hai khác biệt cố ý:)
///
/// - There is no `originalAppUserId`: no vendor assigns an identity. Use
///   `TNSubscriptionCore.clientId` if your own backend needs one.
///   (Không có `originalAppUserId`: không nhà cung cấp nào gán danh tính. Hãy dùng
///   `TNSubscriptionCore.clientId` nếu backend của bạn cần một ID.)
/// - `nonSubscriptionProductIdentifiers` lists lifetime (non-consumable) purchases only.
///   Consumables are finished and forgotten by design; track those balances yourself
///   (see `TNConsumableManager`).
///   (`nonSubscriptionProductIdentifiers` chỉ liệt kê các giao dịch vĩnh viễn (non-consumable).
///   Consumable được cố ý hoàn tất rồi quên đi; bạn tự theo dõi số dư của chúng —
///   xem `TNConsumableManager`.)
public struct TNCustomerInfo: Hashable, Sendable {

    /// The state of every configured entitlement.
    /// (Trạng thái của mọi quyền lợi đã cấu hình.)
    public let entitlements: TNEntitlementInfos

    /// Product IDs of currently active auto-renewable subscriptions.
    /// (Product ID của các subscription tự gia hạn đang hoạt động.)
    public let activeSubscriptions: Set<String>

    /// Product IDs of every product this Apple ID currently owns, subscriptions and lifetime alike.
    /// (Product ID của mọi sản phẩm Apple ID này đang sở hữu, cả subscription và vĩnh viễn.)
    public let allPurchasedProductIdentifiers: Set<String>

    /// Product IDs of owned non-consumable (lifetime) products.
    /// (Product ID của các sản phẩm non-consumable (vĩnh viễn) đang sở hữu.)
    public let nonSubscriptionProductIdentifiers: Set<String>

    /// The furthest-out expiration date across all active subscriptions.
    /// `nil` when nothing is active, or when the only entitlement is a lifetime purchase.
    /// (Ngày hết hạn xa nhất trong tất cả subscription đang hoạt động. `nil` khi không có gì
    /// hoạt động, hoặc khi quyền lợi duy nhất là một giao dịch vĩnh viễn.)
    public let latestExpirationDate: Date?

    /// The earliest purchase date seen across all transactions — effectively "customer since".
    /// (Ngày mua sớm nhất trong mọi giao dịch — tức là "khách hàng từ khi nào".)
    public let originalPurchaseDate: Date?

    /// When this snapshot was taken.
    /// (Thời điểm snapshot này được tạo.)
    public let requestDate: Date

    /// The URL of Apple's subscription management screen.
    /// (URL màn hình quản lý đăng ký của Apple.)
    public let managementURL: URL? = URL(string: "https://apps.apple.com/account/subscriptions")

    /// `true` when at least one entitlement is active.
    /// (`true` khi có ít nhất một quyền lợi đang hoạt động.)
    public var hasActiveEntitlement: Bool { !entitlements.active.isEmpty }

    public init(
        entitlements: TNEntitlementInfos = TNEntitlementInfos(),
        activeSubscriptions: Set<String> = [],
        allPurchasedProductIdentifiers: Set<String> = [],
        nonSubscriptionProductIdentifiers: Set<String> = [],
        latestExpirationDate: Date? = nil,
        originalPurchaseDate: Date? = nil,
        requestDate: Date = Date()
    ) {
        self.entitlements = entitlements
        self.activeSubscriptions = activeSubscriptions
        self.allPurchasedProductIdentifiers = allPurchasedProductIdentifiers
        self.nonSubscriptionProductIdentifiers = nonSubscriptionProductIdentifiers
        self.latestExpirationDate = latestExpirationDate
        self.originalPurchaseDate = originalPurchaseDate
        self.requestDate = requestDate
    }
}

// MARK: - Transaction Mapping

extension StoreKit.Transaction {

    /// The pricing phase this transaction represents.
    /// (Giai đoạn giá mà giao dịch này đại diện.)
    var tn_periodType: TNPeriodType {
        if #available(iOS 17.2, *) {
            switch offer?.type {
            case .introductory:
                // StoreKit does not say free-vs-paid intro on the transaction; the product's
                // offer does. `.trial` is resolved later, where the product is available.
                return .intro
            case .promotional, .code:
                return .promotional
            case .winBack:
                return .promotional
            case .none:
                return .normal
            default:
                return .normal
            }
        } else {
            switch offerType {
            case .introductory:
                return .intro
            case .promotional, .code:
                return .promotional
            case .none:
                return .normal
            default:
                return .normal
            }
        }
    }

    /// How the Apple ID owns this product.
    /// (Apple ID sở hữu sản phẩm này theo cách nào.)
    var tn_ownershipType: TNOwnershipType {
        switch ownershipType {
        case .purchased: return .purchased
        case .familyShared: return .familyShared
        default: return .unknown
        }
    }

    /// `true` when this came from the sandbox or an Xcode StoreKit configuration file.
    /// (`true` khi giao dịch đến từ sandbox hoặc file cấu hình StoreKit của Xcode.)
    var tn_isSandbox: Bool {
        switch environment {
        case .production: return false
        case .sandbox, .xcode: return true
        default: return true
        }
    }

    /// Where the purchase came from, as far as StoreKit can tell.
    /// (Giao dịch đến từ đâu, trong giới hạn StoreKit có thể cho biết.)
    var tn_store: TNStore {
        if tn_isSandbox { return .sandbox }
        if ownershipType == .familyShared { return .familyShared }
        return .appStore
    }
}

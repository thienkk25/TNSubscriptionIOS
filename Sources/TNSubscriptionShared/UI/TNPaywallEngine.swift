import Foundation
import SwiftUI

// MARK: - What The Paywall Needs

/// What the built-in paywall reads from an engine. Almost every member already exists on the engines
/// under the same name, so conforming is a short extension plus the `paywall…` adapters.
/// (Những gì paywall có sẵn đọc từ một engine. Hầu hết thành viên đã có sẵn trên engine với cùng tên,
/// nên việc tuân theo chỉ là một extension ngắn cộng với các hàm chuyển đổi `paywall…`.)
@MainActor
package protocol TNPaywallEngine: ObservableObject {
    associatedtype Package: TNPaywallPackage
    associatedtype Offer: TNPaywallOffer
    associatedtype EntitlementInfo: TNPaywallEntitlement
    associatedtype CustomerInfo

    var entitlementState: TNEntitlementState { get }
    var isPremium: Bool { get }
    var activeEntitlements: Set<String> { get }
    var availablePackages: [Package] { get }
    var isLoadingOfferings: Bool { get }
    var isPurchasing: Bool { get }
    var offeringsError: String? { get }
    var currentPlanProductID: String? { get }
    var currentPlanDisplayName: String? { get }

    func hasEntitlement(_ entitlementId: String) -> Bool
    func productIDs(for entitlementId: String) -> Set<String>
    func entitlementInfo(for entitlementId: String) -> EntitlementInfo?
    func isRecommended(_ package: Package) -> Bool
    func resolveEntitlement() async
    func loadOfferings(offeringIdentifier: String?) async
    func fetchOfferings(offeringIdentifier: String?)
    func showManageSubscriptions()
    func purchase(package: Package, completion: @escaping (Result<CustomerInfo, Error>) -> Void)
    func restorePurchases(completion: @escaping (Result<Bool, Error>) -> Void)

    /// The offer the user will get on this package, or `nil` when none applies.
    /// (Ưu đãi người dùng sẽ nhận trên gói này, hoặc `nil` khi không có ưu đãi nào áp dụng.)
    func paywallOffer(for package: Package) -> Offer?

    /// Called once the paywall has loaded. Only vendors that count paywall views need it.
    /// (Được gọi khi paywall đã tải xong. Chỉ nhà cung cấp nào đếm lượt xem paywall mới cần.)
    func paywallDidAppear() async

    /// How to show a failed purchase. The default reads `TNPaywallPurchaseError`; an engine whose
    /// SDK throws its own errors (RevenueCat) maps those too.
    /// (Cách hiển thị một lần mua không thành. Mặc định đọc `TNPaywallPurchaseError`; engine có SDK
    /// tự ném lỗi riêng — RevenueCat — thì map thêm các lỗi đó.)
    func paywallOutcome(for error: Error) -> TNPaywallPurchaseOutcome
}

extension TNPaywallEngine {
    package func paywallDidAppear() async {}

    package func paywallOutcome(for error: Error) -> TNPaywallPurchaseOutcome {
        (error as? any TNPaywallPurchaseError)?.paywallOutcome ?? .failed
    }
}

/// What the paywall shows for a plan. (Những gì paywall hiển thị cho một gói.)
///
/// `paywallPackageType` rather than `packageType`: RevenueCat's `Package` already has a
/// `packageType` of its own type. (Dùng `paywallPackageType` thay vì `packageType`: `Package` của
/// RevenueCat đã có `packageType` với kiểu riêng.)
package protocol TNPaywallPackage: Hashable {
    var identifier: String { get }
    var paywallPackageType: TNPackageType { get }
    var productIdentifier: String { get }
    var localizedPriceString: String { get }
    var localizedTitle: String { get }
    var pricePerMonth: Decimal? { get }
    var localizedPricePerMonth: String? { get }
    func savingsPercentage(comparedTo other: Self) -> Int?
}

/// How the paywall words an offer. (Cách paywall diễn đạt một ưu đãi.)
package enum TNPaywallOfferKind: Sendable {
    case freeTrial, introductory, winBack, other
}

package protocol TNPaywallOffer {
    var paywallKind: TNPaywallOfferKind { get }
    var localizedSummary: String { get }
}

/// The subscription problems the paywall warns about. (Các vấn đề subscription mà paywall cảnh báo.)
package protocol TNPaywallEntitlement {
    var isInGracePeriod: Bool { get }
    var hasBillingIssue: Bool { get }
    var willRenew: Bool { get }
    var expirationDate: Date? { get }
}

/// How a failed purchase should be shown. (Cách hiển thị một giao dịch mua không thành.)
package enum TNPaywallPurchaseOutcome: Sendable {
    /// The user backed out — not an error worth an alert. (Người dùng tự huỷ — không cần báo lỗi.)
    case cancelled
    /// Waiting for approval (Ask to Buy). (Đang chờ duyệt — Ask to Buy.)
    case pending
    case failed
}

package protocol TNPaywallPurchaseError: Error {
    var paywallOutcome: TNPaywallPurchaseOutcome { get }
}

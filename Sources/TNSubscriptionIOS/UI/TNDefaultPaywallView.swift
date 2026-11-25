import SwiftUI
import RevenueCat

// MARK: - TNDefaultPaywallView

/// The built-in paywall, driven entirely by `TNSubscriptionIOS` and `DefaultPaywallConfig`.
/// (Paywall có sẵn, điều khiển hoàn toàn bởi `TNSubscriptionIOS` và `DefaultPaywallConfig`.)
///
/// Use it directly in SwiftUI (`.sheet { TNDefaultPaywallView(config: …) }`), or present it
/// from UIKit with `TNSubscriptionIOS.presentDefaultPaywall(from:config:)`.
/// (Dùng trực tiếp trong SwiftUI (`.sheet { TNDefaultPaywallView(config: …) }`), hoặc hiển thị
/// từ UIKit bằng `TNSubscriptionIOS.presentDefaultPaywall(from:config:)`.)
///
/// The screen itself is `TNPaywallScreen` in TNSubscriptionShared, shared with every engine; this
/// engine only supplies RevenueCat's data, below.
/// (Màn hình thật là `TNPaywallScreen` trong TNSubscriptionShared, dùng chung với mọi engine; engine
/// này chỉ cung cấp dữ liệu RevenueCat, ở bên dưới.)
public struct TNDefaultPaywallView: View {

    public let config: DefaultPaywallConfig

    public init(config: DefaultPaywallConfig = DefaultPaywallConfig()) {
        self.config = config
    }

    public var body: some View {
        TNPaywallScreen(engine: TNSubscriptionIOS.shared, config: config)
    }
}

// MARK: - Paywall Data

extension TNSubscriptionIOS: TNPaywallEngine {

    /// The introductory offer, and only while the user is still eligible for it.
    /// (Ưu đãi người mới, và chỉ khi người dùng còn đủ điều kiện.)
    package func paywallOffer(for package: Package) -> StoreProductDiscount? {
        introOffer(for: package)
    }

    /// RevenueCat reports cancellation and Ask to Buy through its own error codes.
    /// (RevenueCat báo huỷ và Ask to Buy bằng mã lỗi riêng.)
    package func paywallOutcome(for error: Error) -> TNPaywallPurchaseOutcome {
        if let flowError = error as? PurchaseFlowError, case .userCancelled = flowError {
            return .cancelled
        }
        if let code = error as? RevenueCat.ErrorCode {
            switch code {
            case .purchaseCancelledError: return .cancelled
            case .paymentPendingError: return .pending
            default: return .failed
            }
        }
        return .failed
    }
}

extension TNPackageType {
    /// RevenueCat's package type, as the shared one. (Loại gói của RevenueCat, quy về loại dùng chung.)
    init(revenueCat type: PackageType) {
        switch type {
        case .lifetime: self = .lifetime
        case .annual: self = .annual
        case .sixMonth: self = .sixMonth
        case .threeMonth: self = .threeMonth
        case .twoMonth: self = .twoMonth
        case .monthly: self = .monthly
        case .weekly: self = .weekly
        case .custom: self = .custom
        default: self = .unknown
        }
    }
}

extension Package: TNPaywallPackage {
    package var paywallPackageType: TNPackageType { TNPackageType(revenueCat: packageType) }
    package var productIdentifier: String { storeProduct.productIdentifier }
    package var localizedTitle: String { storeProduct.localizedTitle }
    package var pricePerMonth: Decimal? { storeProduct.pricePerMonth?.decimalValue }
    package var localizedPricePerMonth: String? { storeProduct.localizedPricePerMonth }

    package func savingsPercentage(comparedTo other: Package) -> Int? {
        guard let mine = pricePerMonth, let theirs = other.pricePerMonth else { return nil }
        return TNPriceMath.savingsPercentage(perMonth: mine, comparedTo: theirs)
    }
}

extension EntitlementInfo: TNPaywallEntitlement {
    /// RevenueCat keeps access during a grace period, so a billing issue on an active entitlement
    /// is a grace period; on an inactive one it is a billing retry.
    /// (RevenueCat giữ quyền trong grace period, nên lỗi thanh toán trên quyền lợi còn hoạt động là
    /// grace period; trên quyền lợi đã hết là billing retry.)
    package var isInGracePeriod: Bool { billingIssueDetectedAt != nil && isActive }
    package var hasBillingIssue: Bool { billingIssueDetectedAt != nil && !isActive }
}

extension StoreProductDiscount: TNPaywallOffer {
    package var paywallKind: TNPaywallOfferKind {
        guard type == .introductory else { return .other }
        return paymentMode == .freeTrial ? .freeTrial : .introductory
    }

    package var localizedSummary: String {
        TNOfferRules.summary(
            isFreeTrial: paymentMode == .freeTrial,
            localizedPrice: localizedPriceString,
            periodText: TNSubscriptionIOS.formatSubscriptionPeriod(subscriptionPeriod, numberOfPeriods: numberOfPeriods)
        )
    }
}

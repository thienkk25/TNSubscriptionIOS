import SwiftUI

// MARK: - TNDefaultPaywallView

/// The built-in paywall, driven entirely by `TNSubscriptionQonversion` and `DefaultPaywallConfig`.
/// (Paywall có sẵn, điều khiển hoàn toàn bởi `TNSubscriptionQonversion` và `DefaultPaywallConfig`.)
///
/// Use it directly in SwiftUI (`.sheet { TNDefaultPaywallView(config: …) }`), or present it
/// from UIKit with `TNSubscriptionQonversion.presentDefaultPaywall(from:config:)`.
/// (Dùng trực tiếp trong SwiftUI (`.sheet { TNDefaultPaywallView(config: …) }`), hoặc hiển thị
/// từ UIKit bằng `TNSubscriptionQonversion.presentDefaultPaywall(from:config:)`.)
///
/// The screen itself is `TNPaywallScreen` in TNSubscriptionShared, shared with every engine; this
/// engine only supplies the data, below.
/// (Màn hình thật là `TNPaywallScreen` trong TNSubscriptionShared, dùng chung với mọi engine; engine
/// này chỉ cung cấp dữ liệu, ở bên dưới.)
public struct TNDefaultPaywallView: View {

    public let config: DefaultPaywallConfig

    public init(config: DefaultPaywallConfig = DefaultPaywallConfig()) {
        self.config = config
    }

    public var body: some View {
        TNPaywallScreen(engine: TNSubscriptionQonversion.shared, config: config)
    }
}

// MARK: - Paywall Data

extension TNSubscriptionQonversion: TNPaywallEngine {

    /// The paywall shows the introductory offer, and only while the user is still eligible for it.
    /// (Paywall hiển thị ưu đãi mà người dùng thật sự sẽ nhận.)
    package func paywallOffer(for package: TNPackage) -> TNSubscriptionOffer? {
        introOffer(for: package)
    }
}

extension TNPackage: TNPaywallPackage {
    package var paywallPackageType: TNPackageType { packageType }
}

extension TNEntitlementInfo: TNPaywallEntitlement {}

extension TNSubscriptionOffer: TNPaywallOffer {
    package var paywallKind: TNPaywallOfferKind {
        switch type {
        case .introductory: return paymentMode == .freeTrial ? .freeTrial : .introductory
        case .winBack: return .winBack
        default: return .other
        }
    }
}

extension TNPurchaseError: TNPaywallPurchaseError {
    package var paywallOutcome: TNPaywallPurchaseOutcome {
        switch self {
        case .userCancelled: return .cancelled
        case .purchasePending: return .pending
        default: return .failed
        }
    }
}

import SwiftUI

// MARK: - TNDefaultPaywallView

/// The built-in paywall, driven entirely by `TNSubscriptionCore` and `DefaultPaywallConfig`.
/// (Paywall có sẵn, điều khiển hoàn toàn bởi `TNSubscriptionCore` và `DefaultPaywallConfig`.)
///
/// Use it directly in SwiftUI (`.sheet { TNDefaultPaywallView(config: …) }`), or present it
/// from UIKit with `TNSubscriptionCore.presentDefaultPaywall(from:config:)`.
/// (Dùng trực tiếp trong SwiftUI (`.sheet { TNDefaultPaywallView(config: …) }`), hoặc hiển thị
/// từ UIKit bằng `TNSubscriptionCore.presentDefaultPaywall(from:config:)`.)
///
/// The screen itself is `TNPaywallScreen` in TNSubscriptionKit, shared with the other engines that
/// run StoreKit 2 themselves; this engine only supplies the data, below.
/// (Màn hình thật là `TNPaywallScreen` trong TNSubscriptionKit, dùng chung với các engine khác tự
/// chạy StoreKit 2; engine này chỉ cung cấp dữ liệu, ở bên dưới.)
public struct TNDefaultPaywallView: View {

    public let config: DefaultPaywallConfig

    public init(config: DefaultPaywallConfig = DefaultPaywallConfig()) {
        self.config = config
    }

    public var body: some View {
        TNPaywallScreen(engine: TNSubscriptionCore.shared, config: config)
    }
}

// MARK: - Paywall Data

extension TNSubscriptionCore: TNPaywallEngine {

    /// The paywall shows the introductory offer, and only while the user is still eligible for it.
    /// (Paywall hiển thị ưu đãi mà người dùng thật sự sẽ nhận.)
    package func paywallOffer(for package: TNPackage) -> TNSubscriptionOffer? {
        introOffer(for: package)
    }
}

extension TNPackage: TNPaywallPackage {}

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

import Foundation
import SwiftUI
import UIKit

// MARK: - What The Paywall Needs

/// What the built-in paywall reads from an engine. Every member already exists on the engines
/// under the same name, so conforming is a one-line extension plus the `paywall…` adapters.
/// (Những gì paywall có sẵn đọc từ một engine. Mọi thành viên đã có sẵn trên engine với cùng tên,
/// nên việc tuân theo chỉ là một extension một dòng cộng với các hàm chuyển đổi `paywall…`.)
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
}

extension TNPaywallEngine {
    package func paywallDidAppear() async {}
}

/// What the paywall shows for a plan. (Những gì paywall hiển thị cho một gói.)
package protocol TNPaywallPackage: Identifiable, Hashable {
    var identifier: String { get }
    var packageType: TNPackageType { get }
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

// MARK: - UIKit Presentation

/// Presents a SwiftUI paywall modally from UIKit. (Hiển thị paywall SwiftUI dạng modal từ UIKit.)
@MainActor
package enum TNPaywallPresentation {

    package static func present<Content: View>(_ view: Content, from viewController: UIViewController) {
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet

        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }

        // Presenting from a controller that already has something presented silently does
        // nothing, so walk to the top of the stack first.
        topMost(from: viewController).present(host, animated: true)
    }

    /// Walks the hierarchy to the controller actually on screen.
    /// (Đi theo cây view controller tới controller đang thật sự hiển thị.)
    package static func topMost(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topMost(from: presented)
        }
        if let navigation = controller as? UINavigationController {
            return navigation.visibleViewController.map(topMost(from:)) ?? navigation
        }
        if let tab = controller as? UITabBarController {
            return tab.selectedViewController.map(topMost(from:)) ?? tab
        }
        return controller
    }
}

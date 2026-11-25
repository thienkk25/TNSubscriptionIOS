import Foundation
import StoreKit

// MARK: - TNStoreKitGrants

/// What the Apple ID owns right now, read from `Transaction.currentEntitlements`, and which
/// transaction grants each configured entitlement.
/// (Apple ID đang sở hữu gì, đọc từ `Transaction.currentEntitlements`, và giao dịch nào cấp từng
/// quyền lợi đã cấu hình.)
///
/// Core uses it as its source of truth; Adapty and Qonversion use it as their offline fallback.
/// Each engine then builds its own `TNEntitlementInfo` from the chosen transactions.
/// (Core dùng nó làm nguồn chân lý; Adapty và Qonversion dùng làm phương án dự phòng khi offline.
/// Mỗi engine tự dựng `TNEntitlementInfo` của mình từ các giao dịch được chọn.)
package struct TNStoreKitGrants {
    /// The transaction granting each entitlement: the one that lasts longest, so a lifetime
    /// purchase (no expiry) beats any subscription.
    /// (Giao dịch cấp từng quyền lợi: giao dịch kéo dài nhất, nên mua vĩnh viễn (không hết hạn) thắng
    /// mọi subscription.)
    package private(set) var transactions: [String: StoreKit.Transaction] = [:]
    package private(set) var ownedProductIDs: Set<String> = []
    package private(set) var subscriptionProductIDs: Set<String> = []
    package private(set) var nonSubscriptionProductIDs: Set<String> = []
    /// Over every entitling transaction, matched or not. (Tính trên mọi giao dịch còn hiệu lực.)
    package private(set) var latestExpiration: Date?
    package private(set) var earliestPurchase: Date?
    package private(set) var inspected = 0
    package private(set) var unverified = 0

    package static func current(for entitlements: [TNEntitlement], now: Date = Date()) async -> TNStoreKitGrants {
        var grants = TNStoreKitGrants()
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                grants.unverified += 1
                TNLog.warn("Skipping an UNVERIFIED StoreKit transaction (failed on-device JWS validation).")
                continue
            }
            grants.add(transaction, entitlements: entitlements, now: now)
        }
        return grants
    }

    /// Takes one verified transaction into account. Separate from `current` so tests can feed it.
    /// (Xét một giao dịch đã xác minh. Tách khỏi `current` để test có thể truyền vào.)
    package mutating func add(_ transaction: StoreKit.Transaction, entitlements: [TNEntitlement], now: Date) {
        inspected += 1
        guard transaction.tn_isEntitling(asOf: now) else {
            TNLog.debug("Skipping \(transaction.productID): revoked=\(transaction.revocationDate != nil), expiry=\(transaction.expirationDate.map(String.init(describing:)) ?? "none").")
            return
        }

        ownedProductIDs.insert(transaction.productID)
        if transaction.productType == .autoRenewable {
            subscriptionProductIDs.insert(transaction.productID)
        } else if transaction.productType == .nonConsumable {
            nonSubscriptionProductIDs.insert(transaction.productID)
        }
        if let expiry = transaction.expirationDate {
            latestExpiration = max(latestExpiration ?? expiry, expiry)
        }
        earliestPurchase = min(earliestPurchase ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)

        let matched = entitlements.filter { $0.productIDs.contains(transaction.productID) }
        if matched.isEmpty {
            TNLog.debug("""
            StoreKit transaction for \(transaction.productID) matched NO configured entitlement. \
            Configured product IDs: \(Set(entitlements.flatMap(\.productIDs)).sorted()).
            """)
            return
        }
        for entitlement in matched {
            if let existing = transactions[entitlement.id],
               !Self.lastsLonger(transaction.expirationDate, than: existing.expirationDate) {
                continue
            }
            transactions[entitlement.id] = transaction
        }
    }

    /// `nil` means no expiry (a lifetime purchase), which outlasts every date.
    /// (`nil` nghĩa là không hết hạn — mua vĩnh viễn — nên dài hơn mọi ngày.)
    package static func lastsLonger(_ candidate: Date?, than existing: Date?) -> Bool {
        (candidate ?? .distantFuture) > (existing ?? .distantFuture)
    }
}

extension StoreKit.Transaction {
    /// Not revoked and not expired. (Chưa bị thu hồi và chưa hết hạn.)
    package func tn_isEntitling(asOf now: Date = Date()) -> Bool {
        guard revocationDate == nil else { return false }
        if let expirationDate { return expirationDate > now }
        return true
    }
}

// MARK: - Offers

/// Offer rules shared by every engine. (Quy tắc ưu đãi dùng chung cho mọi engine.)
package enum TNOfferRules {

    /// `"3 Days Free Trial"` or `"$0.99 for 1 Month"`. One wording, so every engine says the same.
    /// (`"Dùng thử miễn phí 3 Ngày"` hoặc `"0,99 US$ cho 1 Tháng"`. Một cách diễn đạt, để mọi engine
    /// nói giống nhau.)
    package static func summary(isFreeTrial: Bool, localizedPrice: String, periodText: String) -> String {
        isFreeTrial
            ? String(format: NSLocalizedString("%@ Free Trial", comment: ""), periodText)
            : String(format: NSLocalizedString("%@ for %@", comment: ""), localizedPrice, periodText)
    }

    /// The offer's type and payment mode as raw values of the engines' `TNOfferType` and
    /// `TNOfferPaymentMode`; `nil` for kinds an engine cannot represent.
    /// (Loại ưu đãi và cách thanh toán dưới dạng raw value của `TNOfferType` và `TNOfferPaymentMode`
    /// của engine; `nil` với loại engine không biểu diễn được.)
    ///
    /// There is no `.code` case: an offer code is never configured on a product — it only appears on
    /// a *transaction*, after the user redeems it.
    /// (Không có `.code`: offer code không bao giờ được cấu hình trên sản phẩm — nó chỉ xuất hiện trên
    /// *giao dịch*, sau khi người dùng nhập code.)
    package static func storeKitKind(of offer: Product.SubscriptionOffer) -> (type: String, paymentMode: String)? {
        let paymentMode: String
        switch offer.paymentMode {
        case .freeTrial: paymentMode = "freeTrial"
        case .payUpFront: paymentMode = "payUpFront"
        case .payAsYouGo: paymentMode = "payAsYouGo"
        default: return nil
        }
        switch offer.type {
        case .introductory: return ("introductory", paymentMode)
        case .promotional: return ("promotional", paymentMode)
        default:
            if #available(iOS 18.0, *), offer.type == .winBack { return ("winBack", paymentMode) }
            return nil
        }
    }
}

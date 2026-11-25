import Foundation
import StoreKit

// `TNIntroEligibilityStatus` lives in TNSubscriptionShared. (`TNIntroEligibilityStatus` nằm trong TNSubscriptionShared.)

// MARK: - TNOfferPaymentMode

/// How an offer charges the user.
/// (Cách ưu đãi thu phí người dùng.)
public enum TNOfferPaymentMode: String, Hashable, Sendable {
    /// Free for the offer period.
    /// (Miễn phí trong thời gian ưu đãi.)
    case freeTrial
    /// A reduced price charged once up front for the whole offer period.
    /// (Trả trước một lần với giá giảm cho toàn bộ thời gian ưu đãi.)
    case payUpFront
    /// A reduced price charged each period, for a number of periods.
    /// (Trả giá giảm theo từng kỳ, trong một số kỳ nhất định.)
    case payAsYouGo
}

// MARK: - TNOfferType

/// Which kind of discount an offer is.
/// (Loại ưu đãi.)
public enum TNOfferType: String, Hashable, Sendable {
    /// For users who never subscribed in this group. Applied automatically by StoreKit.
    /// (Dành cho người chưa từng đăng ký trong group này. StoreKit tự áp dụng.)
    case introductory
    /// For existing or lapsed subscribers. **Requires a server-signed signature.**
    /// (Dành cho người đang/đã từng đăng ký. **Bắt buộc có chữ ký từ server.**)
    case promotional
    /// Redeemed by the user through Apple's Offer Code sheet.
    /// (Người dùng tự nhập qua bảng Offer Code của Apple.)
    case offerCode
    /// iOS 18+: targets users who cancelled, surfaced by Apple itself.
    /// (iOS 18+: nhắm tới người đã huỷ, do Apple tự hiển thị.)
    case winBack
}

// MARK: - TNSubscriptionOffer

/// A discount available on a subscription product.
/// (Một ưu đãi giảm giá áp dụng cho sản phẩm subscription.)
///
/// The local replacement for RevenueCat's `StoreProductDiscount`, wrapping
/// `Product.SubscriptionOffer`.
/// (Bản thay thế cục bộ cho `StoreProductDiscount` của RevenueCat, bọc quanh
/// `Product.SubscriptionOffer`.)
public struct TNSubscriptionOffer: Identifiable, Hashable, Sendable {

    /// The offer identifier from App Store Connect. `nil` for introductory offers,
    /// which Apple allows only one of per subscription group.
    /// (ID của ưu đãi trên App Store Connect. `nil` với ưu đãi người mới, vì Apple chỉ
    /// cho phép một ưu đãi người mới cho mỗi subscription group.)
    public let offerIdentifier: String?

    /// The product this offer belongs to.
    /// (Sản phẩm mà ưu đãi này thuộc về.)
    public let productIdentifier: String

    /// Which kind of discount this is.
    /// (Loại ưu đãi.)
    public let type: TNOfferType

    /// How the user is charged during the offer.
    /// (Cách thu phí trong thời gian ưu đãi.)
    public let paymentMode: TNOfferPaymentMode

    /// The offer price. `0` for a free trial.
    /// (Giá của ưu đãi. Bằng `0` nếu là dùng thử miễn phí.)
    public let price: Decimal

    /// The offer price formatted in the store's currency (e.g. `"$0.99"`).
    /// (Giá ưu đãi đã định dạng theo tiền tệ của store, ví dụ `"0,99 $"`.)
    public let localizedPriceString: String

    /// The length of one offer period.
    /// (Độ dài của một kỳ ưu đãi.)
    public let period: Product.SubscriptionPeriod

    /// How many times the offer period repeats (always `1` except for `payAsYouGo`).
    /// (Số kỳ ưu đãi được lặp lại — luôn là `1`, trừ trường hợp `payAsYouGo`.)
    public let periodCount: Int

    /// The underlying StoreKit offer, in case you need a field this struct does not expose.
    /// (Đối tượng StoreKit gốc, dùng khi bạn cần một thuộc tính mà struct này chưa expose.)
    public let storeKitOffer: Product.SubscriptionOffer

    public var id: String { "\(productIdentifier):\(type.rawValue):\(offerIdentifier ?? "intro")" }

    /// A localised summary such as `"3 Days Free Trial"` or `"$0.99 for 1 Month"`.
    /// (Mô tả đã dịch, ví dụ `"Dùng thử miễn phí 3 Ngày"` hoặc `"0,99 $ trong 1 Tháng"`.)
    public var localizedSummary: String {
        TNOfferRules.summary(
            isFreeTrial: paymentMode == .freeTrial,
            localizedPrice: localizedPriceString,
            periodText: period.localizedDescription(numberOfPeriods: periodCount)
        )
    }

    init?(storeKitOffer: Product.SubscriptionOffer, product: Product) {
        // The mapping rules live in TNSubscriptionShared; only the public types are this engine's.
        guard let kind = TNOfferRules.storeKitKind(of: storeKitOffer),
              let resolvedType = TNOfferType(rawValue: kind.type),
              let paymentMode = TNOfferPaymentMode(rawValue: kind.paymentMode) else { return nil }

        self.storeKitOffer = storeKitOffer
        self.productIdentifier = product.id
        self.offerIdentifier = storeKitOffer.id
        self.type = resolvedType
        self.paymentMode = paymentMode
        self.price = storeKitOffer.price
        self.localizedPriceString = storeKitOffer.displayPrice
        self.period = storeKitOffer.period
        self.periodCount = storeKitOffer.periodCount
    }

    public static func == (lhs: TNSubscriptionOffer, rhs: TNSubscriptionOffer) -> Bool {
        lhs.id == rhs.id && lhs.price == rhs.price
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

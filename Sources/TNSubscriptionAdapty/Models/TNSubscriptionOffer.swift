import Foundation
import Adapty

// `TNIntroEligibilityStatus` lives in TNSubscriptionShared. (`TNIntroEligibilityStatus` nằm trong TNSubscriptionShared.)

// MARK: - TNOfferPaymentMode

/// How an offer charges the user. (Cách ưu đãi thu phí người dùng.)
public enum TNOfferPaymentMode: String, Hashable, Sendable {
    /// Free for the offer period. (Miễn phí trong thời gian ưu đãi.)
    case freeTrial
    /// A reduced price paid once up front. (Trả trước một lần với giá giảm.)
    case payUpFront
    /// A reduced price paid each period. (Trả giá giảm theo từng kỳ.)
    case payAsYouGo
    /// A mode this version does not recognise. (Một hình thức mà phiên bản này chưa biết.)
    case unknown

    init(_ mode: AdaptySubscriptionOffer.PaymentMode) {
        switch mode {
        case .freeTrial: self = .freeTrial
        case .payUpFront: self = .payUpFront
        case .payAsYouGo: self = .payAsYouGo
        default: self = .unknown
        }
    }
}

// MARK: - TNOfferType

/// Which kind of discount an offer is. (Loại ưu đãi.)
public enum TNOfferType: String, Hashable, Sendable {
    /// For users new to the subscription group. (Dành cho người mới với subscription group.)
    case introductory
    /// For existing or lapsed subscribers. Adapty signs it server-side — no key in the app.
    /// (Dành cho người đang/đã từng đăng ký. Adapty ký phía server — không cần key trong app.)
    case promotional
    /// iOS 18+ offer for users who cancelled. (Ưu đãi iOS 18+ cho người đã huỷ.)
    case winBack
    /// An offer type this version does not recognise. (Loại ưu đãi phiên bản này chưa biết.)
    case unknown

    init(_ type: AdaptySubscriptionOfferType) {
        switch type {
        case .introductory: self = .introductory
        case .promotional: self = .promotional
        case .winBack: self = .winBack
        default: self = .unknown
        }
    }
}

// MARK: - TNSubscriptionOffer

/// The offer a user will get on a package, as chosen by Adapty.
/// (Ưu đãi mà người dùng sẽ nhận được trên một gói, do Adapty chọn.)
///
/// ### How this differs from `TNSubscriptionCore` (Khác `TNSubscriptionCore` thế nào)
/// Core lists every offer and leaves eligibility and signing to you. Adapty hands back **one**
/// offer per product, already filtered for this user — priority win-back → promotional →
/// introductory — and `makePurchase` applies it automatically, signing a promotional offer on
/// Adapty's server. So there is no eligibility call and no offer signer to install.
/// (Core liệt kê mọi ưu đãi và để bạn tự lo điều kiện và chữ ký. Adapty trả về **một** ưu đãi cho
/// mỗi sản phẩm, đã lọc sẵn cho người dùng này — ưu tiên win-back → promotional → introductory —
/// và `makePurchase` tự áp dụng nó, ký promotional offer trên server của Adapty. Vì vậy không cần
/// gọi kiểm tra điều kiện và không cần gắn signer.)
public struct TNSubscriptionOffer: Identifiable, Hashable, Sendable {

    /// The App Store Connect offer ID. `nil` for an introductory offer.
    /// (ID ưu đãi trên App Store Connect. `nil` với ưu đãi người mới.)
    public let offerIdentifier: String?

    /// The product this offer belongs to. (Sản phẩm mà ưu đãi này thuộc về.)
    public let productIdentifier: String

    /// Which kind of discount this is. (Loại ưu đãi.)
    public let type: TNOfferType

    /// How the user is charged during the offer. (Cách thu phí trong thời gian ưu đãi.)
    public let paymentMode: TNOfferPaymentMode

    /// The offer price. `0` for a free trial. (Giá ưu đãi. Bằng `0` nếu là dùng thử miễn phí.)
    public let price: Decimal

    /// The offer price in the store's currency. (Giá ưu đãi theo tiền tệ của store.)
    public let localizedPriceString: String

    /// The raw Adapty offer. (Ưu đãi gốc của Adapty.)
    public let adaptyOffer: AdaptySubscriptionOffer

    public var id: String { "\(productIdentifier):\(type.rawValue):\(offerIdentifier ?? "intro")" }

    /// A localised summary such as `"3 Days Free Trial"` or `"$0.99 for 1 Month"`.
    /// (Mô tả đã dịch, ví dụ `"Dùng thử miễn phí 3 Ngày"` hoặc `"0,99 $ trong 1 Tháng"`.)
    public var localizedSummary: String {
        let period = adaptyOffer.subscriptionPeriod
        let periodText = Self.periodText(
            unit: period.unit,
            count: period.numberOfUnits * max(1, adaptyOffer.numberOfPeriods)
        )
        return TNOfferRules.summary(
            isFreeTrial: paymentMode == .freeTrial,
            localizedPrice: localizedPriceString,
            periodText: periodText
        )
    }

    init(adaptyOffer: AdaptySubscriptionOffer, productIdentifier: String) {
        self.adaptyOffer = adaptyOffer
        self.productIdentifier = productIdentifier
        self.offerIdentifier = adaptyOffer.identifier
        self.type = TNOfferType(adaptyOffer.offerType)
        self.paymentMode = TNOfferPaymentMode(adaptyOffer.paymentMode)
        self.price = adaptyOffer.price
        self.localizedPriceString = adaptyOffer.localizedPrice
    }

    static func periodText(unit: AdaptySubscriptionPeriod.Unit, count: Int) -> String {
        switch unit {
        case .day: return TNPeriodFormatter.string(unit: .day, count: count)
        case .week: return TNPeriodFormatter.string(unit: .week, count: count)
        case .month: return TNPeriodFormatter.string(unit: .month, count: count)
        case .year: return TNPeriodFormatter.string(unit: .year, count: count)
        default: return "\(max(1, count))"
        }
    }

    public static func == (lhs: TNSubscriptionOffer, rhs: TNSubscriptionOffer) -> Bool {
        lhs.id == rhs.id && lhs.price == rhs.price
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
